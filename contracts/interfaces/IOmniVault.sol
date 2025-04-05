// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOmniVault {
    event TotalSupplyUpdated(uint32 chainId, uint256 totalSupply, uint256 reqId);

    enum ProtocolType {
        AAVE,
        COMPOUND,
        CCTP,
        HYPERLANE,
        HYPERLANE_GAS_PAYMASTER
    }

    struct Path {
        uint32 actionChainId; // Defi Action ChainId
        ProtocolType protocolId;
        uint256 amount;
        address recipient; // crossChainWithdraw 에서 사용
    }

    // manager (owner)
    // Path example: [ (11155111, ProtocolType.AAVE, 1 * 10**6, address(0)), (84532, ProtocolType.COMPOUND, 1 * 10**6, address(0)) ]
    function withdrawAndBridgeAndDeposit(Path[] memory actions) external;

    // user
    // Path example: [ (11155111, ProtocolType.AAVE, 1 * 10**6, address(user)) ]
    function deposit(Path[] memory actions) external;

    // user
    // Path example: [ (11155111, ProtocolType.AAVE, 1 * 10**6, address(user)) ]
    function withdraw(Path[] memory actions) external;

    // 다른체인의 totalSupply 를 요청 (원래 chainID 를 파라미터로 받지만 지금은 필요없음)
    function requestTotalSupply(uint256 reqId) external;

    // 현재체인에서 볼트가 얼마나 들고 있는지 조회
    function totalSupply() external view returns (uint256);

    // 프로토콜이 얼마나 만들어졌는지 조회 & lsdCore 호출
    function applyInterest() external;
}
