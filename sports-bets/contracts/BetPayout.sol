pragma solidity ^0.4.17;

import "./SportsBets.sol";
import "./SafeMath.sol";
import "./OracleInterface.sol";


contract BetPayout is SportsBets {

    using SafeMath for uint; 

    //constants 
    uint housePercentage = 1; 
    uint multFactor = 1000000;

    function _payOutBet(address user, uint amount) private {
        user.transfer(amount);
    }

    function _transferToHouse() private {
        owner.transfer(address(this).balance);
    }

    function _isWinningBet(OracleInterface.MatchOutcome _outcome, uint8 _chosenWinner, int8 _actualWinner) private pure returns (bool) {
        return _outcome == OracleInterface.MatchOutcome.Decided && _chosenWinner >= 0 && (_chosenWinner == uint8(_actualWinner)); 
    }

    function _calculatePayout(uint _winningTotal, uint _totalPot, uint _betAmount) private view returns (uint) {
        //calculate proportion
        uint proportion = (_betAmount.mul(multFactor)).div(_winningTotal);
        
        //calculate raw share
        uint rawShare = _totalPot.mul(proportion).div(multFactor);

        //if share has been rounded down to zero, fix that 
        if (rawShare == 0) 
            rawShare = minimumBet;
        
        //take out house's cut 
        rawShare = rawShare/(100 * housePercentage);
        return rawShare;
    }

    function _payOutForMatch(bytes32 _matchId, OracleInterface.MatchOutcome _outcome, int8 _winner) private {
    
        Bet[] storage bets = matchToBets[_matchId]; 
        uint losingTotal = 0; 
        uint winningTotal = 0; 
        uint totalPot = 0;
        uint[] memory payouts = new uint[](bets.length);
        
        //count winning bets & get total 
        uint n;
        for (n = 0; n < bets.length; n++) {
            uint amount = bets[n].amount;
            if (_isWinningBet(_outcome, bets[n].chosenWinner, _winner)) {
                winningTotal = winningTotal.add(amount);
            } else {
                losingTotal = losingTotal.add(amount);
            }
        }
        totalPot = (losingTotal.add(winningTotal)); 

        //calculate payouts per bet 
        for (n = 0; n < bets.length; n++) {
            if (_outcome == OracleInterface.MatchOutcome.Draw) {
                payouts[n] = bets[n].amount;
            } else {
                if (_isWinningBet(_outcome, bets[n].chosenWinner, _winner)) {
                    payouts[n] = _calculatePayout(winningTotal, totalPot, bets[n].amount); 
                } else {
                    payouts[n] = 0;
                }
            }
        }

        //pay out the payouts 
        for (n = 0; n < payouts.length; n++) {
            _payOutBet(bets[n].user, payouts[n]); 
        }

        //transfer the remainder to the owner
        _transferToHouse();
    }
    
    
    function checkOutcome(bytes32 _matchId) public returns (OracleInterface.MatchOutcome)  {
        OracleInterface.MatchOutcome outcome; 
        int8 winner = -1;

        (,,,,outcome,winner) = boxingOracle.getMatch(_matchId); 

        if (outcome == OracleInterface.MatchOutcome.Decided) {
            if (!matchPaidOut[_matchId]) {
                _payOutForMatch(_matchId, outcome, winner);
            }
        } 

        return outcome; 
    }
}