// pragma solidity 0.6.12;

// import "@openzeppelin/contracts/math/SafeMath.sol";
// import "./utils/QueueStakesFuns.sol";

// struct QueuePoolInfo {                                                       
//         //LP Token
//         QueueStakes lpQueue;
//         //from LP to priorityQueue
//         QueueStakes priorityQueue;
//         //Single Token
//         QueueStakes pendingQueue;
//         //Queue Total
//         uint256 totalPending;
//         //Total LP amount
//         uint256 totalLP;
//         //index of User index
//         mapping(address => uint32[]) userLP;
//         mapping(address => uint32[]) userPriority;
//         mapping(address => uint32[]) userPending;

// }
// library QueuePoolInfoFuns {
//     using QueueStakesFuns for QueueStakes;
//     using SafeMath for uint256;     

//     event Test256(string _msg, address _user ,uint256 _amount);
//     event Test32(string _msg, address _user ,uint32 _amount);
//     function create(QueuePoolInfo storage self, uint32 _size) public {
//         self.lpQueue.create(_size);
//         self.priorityQueue.create(_size);
//         self.pendingQueue.create(_size);
//     }
//     //add to quequeEnd
//     function toQueue(QueuePoolInfo storage self, address _user,  uint256 _amount) public {
//         uint32 pIndex =  self.pendingQueue.append(UserStake({ user: _user, amount: _amount}));
//         self.totalPending = self.totalPending.add(_amount);
//         self.userPending[_user].push(pIndex);
//     }
//     // untake from pendingQueue && priorityQueue
//     function untakePending(QueuePoolInfo storage self, address _user,  uint256 _amount) public {
//         self.totalPending = self.totalPending.sub(_amount);
//         uint32[] storage pQueueIndex = self.userPending[_user];
//         uint256 untakeAmount;

//         while(pQueueIndex.length>0) {
//             uint32 pIndex = pQueueIndex[pQueueIndex.length.sub(1)];
//             UserStake storage userStake = self.pendingQueue.indexOf(pIndex);
//             uint256 amount = userStake.amount;
//             if(untakeAmount.add(amount)>= _amount) {
//                 userStake.amount = untakeAmount.add(amount).sub(_amount);
//                 untakeAmount = _amount;    
//                 break;
//             }else{
//                 untakeAmount = untakeAmount.add(amount);
//                 userStake.amount = 0;
//                 pQueueIndex.pop();
//             }
//         }
//         if (untakeAmount < _amount) {
//             uint256 untakeProority = untakePriority(self, _user, _amount.sub(untakeAmount));
//             untakeAmount = untakeAmount.add(untakeProority);
//         }
//     }

//     function untakePriority(QueuePoolInfo storage self, address _user,  uint256 _amount) internal returns(uint256 burnAuntakeAmountmount) {
//          uint32[] storage priorityIndex = self.userPriority[_user];
//          uint256 untakeAmount;
//          if( priorityIndex.length>0 ) {
//             uint32 pIndex = priorityIndex[priorityIndex.length.sub(1)];
//             UserStake storage userStake = self.priorityQueue.indexOf(pIndex);
//             uint256 amount = userStake.amount;
//             if(untakeAmount.add(amount)>= _amount) {
//                 userStake.amount = untakeAmount.add(amount).div(_amount);
//                 return _amount;
//             }else{
//                 untakeAmount = untakeAmount.add(amount);
//                 userStake.amount = 0;
//                 priorityIndex.pop();
//             }
//          }
//          return untakeAmount;
//     }

//     function pending2LP(QueuePoolInfo storage self,uint256 _pAmoung, uint256 _liquidity) public {
//         // lpRate
//         uint256 lpPreShare =  _pAmoung.mul(1e12).div(_liquidity);

//     }
//     /**
//      * @dev _amount , totoal amount to LP 
//      * return left Amount to LP , pick from pendingQueue
//      */
//     function untakePriority2LP(QueuePoolInfo storage self, uint256 _amount , uint256 lpPreShare) private returns(uint256 untakeAmount) {

//         untakeAmount = _amount;
//         while(self.priorityQueue.length>0) {
//             UserStake storage userStake = self.priorityQueue.first();
//             uint256 amount = userStake.amount;
//             if(amount ==0) { // bean removed todo? is necessary 
//                 self.priorityQueue.remove();
//                 continue;
//             }
//             if(untakeAmount <= amount) {
//                 if(untakeAmount == amount ) {
//                     self.priorityQueue.remove();
//                 }else{
//                     userStake.amount = amount.sub(untakeAmount);
//                 }
//                 appendLP(self, userStake.user, amount,  untakeAmount);
//                 untakeAmount = 0; 
//                 break;
//             }else {
//                 untakeAmount = untakeAmount.sub(amount);
//                 userStake.amount = 0;
//                 self.priorityQueue.remove();
//                 appendLP(self, userStake.user, amount,  lpPreShare);
//             }
//         }
//     }
//     /**
//      * move pending to LP
//      */
//     function appendLP(QueuePoolInfo storage self,address _user, uint _amount, uint _lpRate) private {
//         uint32 pIndex =  self.lpQueue.append(UserStake({ user: _user, amount: _amount}));
//         self.totalLP = self.totalLP.add(_amount);
//         self.userLP[_user].push(pIndex);
//     }

//     /** -------------- VIEW Function --------------- */
//     // function pendingAmount(address _user) public view returns (uint256) {
//     //     uint256 totalPendingAmount;
//     //     //priorityQueue partion
//     //     uint32[] memory prioritys = userPriority[_user];
//     //     for (uint i=0; i< prioritys.length; i++) {
//     //         uint256 amount = priorityQueue.items[uint32(prioritys[i] % priorityQueue.items.length)].amount;
//     //         totalPendingAmount = totalPendingAmount.add(amount);
//     //     }
//     //     //pendingQueue partion
//     //     uint32[] memory pendings = userPending[_user];
//     //     for (uint i=0; i< pendings.length; i++) {
//     //         uint256 amount = pendingQueue.items[uint32(pendings[i] % pendingQueue.items.length)].amount;
//     //         totalPendingAmount = totalPendingAmount.add(amount);
//     //     }
//     //     return totalPendingAmount;
//     // }

//     // function lPAmount(address _user) public view returns (uint256) {
//     //     uint256 totalLPAmount;
//     //     //lpQueue partion
//     //     uint32[] memory lps = userLP[_user];
//     //     for (uint i=0; i< lps.length; i++) {
//     //         uint256 amount = lpQueue.items[uint32(lps[i] % lpQueue.items.length)].amount;
//     //         totalLPAmount = totalLPAmount.add(amount);
//     //     }

//     //     return totalLPAmount;
//     // }
// }