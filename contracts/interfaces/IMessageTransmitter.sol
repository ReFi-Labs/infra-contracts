// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMessageTransmitter {
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external;
}
