// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title BatchCallAndSponsor
 * @notice An educational contract that allows batch execution of calls with nonce and signature verification.
 *
 * When an EOA upgrades via EIP‑7702, it delegates to this implementation.
 * Off‑chain, the account signs a message authorizing a batch of calls. The message is the hash of:
 *    keccak256(abi.encodePacked(nonce, calls))
 * The signature must be generated with the EOA’s private key so that, once upgraded, the recovered signer equals the account’s own address (i.e. address(this)).
 *
 * This contract provides two ways to execute a batch:
 * 1. With a signature: Any sponsor can submit the batch if it carries a valid signature.
 * 2. Directly by the smart account: When the account itself (i.e. address(this)) calls the function, no signature is required.
 *
 * Replay protection uses a bitmap of used nonces. Each nonce is a uint256 where the upper 248 bits
 * select a storage word and the lower 8 bits select a bit within that word. This allows unordered,
 * parallel execution — any nonce can be used or invalidated independently.
 */
contract BatchCallAndSponsor {
    using ECDSA for bytes32;

    /// @notice Bitmap of used nonces. Key is word index (nonce >> 8), value is a 256-bit mask.
    mapping(uint248 => uint256) public nonceBitmap;

    /// @notice Represents a single call within a batch.
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    error NonceAlreadyUsed(uint256 nonce);

    /// @notice Emitted for every individual call executed.
    event CallExecuted(address indexed sender, address indexed to, uint256 value, bytes data);
    /// @notice Emitted when a full batch is executed.
    event BatchExecuted(uint256 indexed nonce, Call[] calls);

    /**
     * @notice Executes a batch of calls using an off–chain signature.
     * @param calls An array of Call structs containing destination, ETH value, and calldata.
     * @param nonce A unique value used for replay protection. Upper 248 bits = word index, lower 8 bits = bit position.
     * @param signature The ECDSA signature over the provided nonce and the call data.
     *
     * The signature must be produced off–chain by signing:
     * The signing key should be the account’s key (which becomes the smart account’s own identity after upgrade).
     */
    function execute(Call[] calldata calls, uint256 nonce, bytes calldata signature) external payable {
        _useNonce(nonce);

        // Compute the digest that the account was expected to sign.
        bytes memory encodedCalls;
        for (uint256 i = 0; i < calls.length; i++) {
            encodedCalls = abi.encodePacked(encodedCalls, calls[i].to, calls[i].value, calls[i].data);
        }
        bytes32 digest = keccak256(abi.encodePacked(nonce, encodedCalls));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(digest);

        address recovered = ECDSA.recover(ethSignedMessageHash, signature);
        require(recovered == address(this), "Invalid signature");

        _executeBatch(nonce, calls);
    }

    /**
     * @notice Executes a batch of calls directly.
     * @dev This function is intended for use when the smart account itself (i.e. address(this))
     * calls the contract. It checks that msg.sender is the contract itself.
     * @param calls An array of Call structs containing destination, ETH value, and calldata.
     */
    function execute(Call[] calldata calls) external payable {
        require(msg.sender == address(this), "Invalid authority");
        for (uint256 i = 0; i < calls.length; i++) {
            _executeCall(calls[i]);
        }
        emit BatchExecuted(0, calls);
    }

    /**
     * @dev Marks a nonce as used. Reverts if it was already used.
     */
    function _useNonce(uint256 nonce) internal {
        uint248 word = uint248(nonce >> 8);
        uint256 mask = uint256(1) << uint8(nonce);
        if (nonceBitmap[word] & mask != 0) revert NonceAlreadyUsed(nonce);
        nonceBitmap[word] |= mask;
    }

    /**
     * @dev Internal function that handles batch execution.
     * @param nonce The nonce used for this batch (already consumed before this call).
     * @param calls An array of Call structs.
     */
    function _executeBatch(uint256 nonce, Call[] calldata calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            _executeCall(calls[i]);
        }

        emit BatchExecuted(nonce, calls);
    }

    /**
     * @dev Internal function to execute a single call.
     * @param callItem The Call struct containing destination, value, and calldata.
     */
    function _executeCall(Call calldata callItem) internal {
        (bool success,) = callItem.to.call{value: callItem.value}(callItem.data);
        require(success, "Call reverted");
        emit CallExecuted(msg.sender, callItem.to, callItem.value, callItem.data);
    }

    // Allow the contract to receive ETH (e.g. from DEX swaps or other transfers).
    fallback() external payable {}
    receive() external payable {}
}
