// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMailBox {
    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody
    ) external view returns (uint256 fee);

    function dispatch(
        uint32 _destination,
        bytes32 _recipient,
        bytes memory _body
    ) external payable returns (bytes32);

    function payForGas(
	    bytes32 _messageId,
	    uint32 _destinationDomain,
	    uint256 _gasAmount,
	    address _refundAddress
    ) external payable;

    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _body
    ) external;
}