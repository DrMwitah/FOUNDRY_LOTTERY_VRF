// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /**
     * Events
     */
    event EnteredRaffle(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);

    Raffle public raffle;
    HelperConfig public helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;

    address public RAFFLE_PLAYER = makeAddr("player");
    uint256 public constant PLAYER_STARTING_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            entranceFee,
            interval,
            vrfCordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            ,

        ) = helperConfig.activeNetworkConfig();

        vm.deal(RAFFLE_PLAYER, PLAYER_STARTING_BALANCE);
    }

    function testRaffleInitializezAtOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    //////////////////////////////
    ///enterRaffle////
    /////////////////////

    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(RAFFLE_PLAYER);
        //Act
        vm.expectRevert(Raffle.Raffle__notEnoughEthSent.selector);
        //Assert
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(RAFFLE_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == RAFFLE_PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(RAFFLE_PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));

        //We emit the event ourselves

        emit EnteredRaffle(RAFFLE_PLAYER);

        //function call that should emit the event

        raffle.enterRaffle{value: entranceFee}();
    }

    ////////////////////////
    ///vm.rolland vm.warp///
    ////////////////////////
    //vm.roll - block.number
    //vm.warp - block.timestamp

    function testCantEnterWhenRaffleISCalculating() public {
        vm.prank(RAFFLE_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpKeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(RAFFLE_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ////////////////////////
    ///checkUpKeep/////////
    //////////////////////

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleNotOpen() public {
        vm.prank(RAFFLE_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpKeep("");
        Raffle.RaffleState rafflestate = raffle.getRaffleState();

        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(rafflestate == Raffle.RaffleState.CALCULATING);
        assert(!upkeepNeeded);
    }

    //testCheckUpKeepReturnsFalseIfEnoughTimeHasntPassed
    //testCheckUpKeepReturnsTrueWhenParametersAreGood

    function testCheckUpKeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(RAFFLE_PLAYER);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(RAFFLE_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + entranceFee + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        assert(upkeepNeeded == true);
    }

    //////////////////////////
    ///performUpKeep    /////
    ////////////////////////

    function testPerformUpKeepCanOnlyRunIfCheckUpKeepIsTrue() public {
        vm.prank(RAFFLE_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + entranceFee + 1);
        vm.roll(block.number + 1);

        raffle.performUpKeep("");
    }

    function testPerformUpKeepRevertsIfCheckUpKeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpKeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(RAFFLE_PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpKeepUPdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs(); //Tells the VM to start recording all the emitted events. To access them, use getRecordedLogs.
        raffle.performUpKeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //Gets the emitted events recorded by recordLogs.This function will consume the recorded logs when called.
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assertEq(entries.length, 2);
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /////////////////////////////////////
    ///fulfillRandomwords////
    ////////////////////////////////////////
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        } else {
            _;
        }
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpKeep(
        uint256 randomRequestId
    ) public skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        //Arrange
        uint256 additionalPlayers = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalPlayers;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, PLAYER_STARTING_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 previousLastTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalPlayers + 1);

        //Act
        vm.recordLogs(); //Tells the VM to start recording all the emitted events. To access them, use getRecordedLogs.
        raffle.performUpKeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs(); //Gets the emitted events recorded by recordLogs.This function will consume the recorded logs when called.
        bytes32 requestId = entries[1].topics[1];

        vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        Vm.Log[] memory winners = vm.getRecordedLogs();
        bytes32 winner = winners[0].topics[1];

        //Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getWinner() != address(0));
        assert(raffle.getPlayersArrayLength() == 0);
        assert(previousLastTimeStamp < raffle.getLastTimeStamp());
        assert(
            raffle.getWinner().balance ==
                prize + PLAYER_STARTING_BALANCE - entranceFee
        );
        assert(uint256(winner) == uint256(uint160(raffle.getWinner())));
    }
}
