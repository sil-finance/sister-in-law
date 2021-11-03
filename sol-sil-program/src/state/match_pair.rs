use super::*;
use crate::error::SilError;
use solana_program::{
    msg,
    entrypoint::ProgramResult,
    program_error::ProgramError,
    program_pack::IsInitialized,
    pubkey::Pubkey,
};
use typenum::{U1000, Bit};

type LIFOUserStakesCapacity = U1000;
type FIFOUserStakesCapacity = U1000;

pub type LIFOUserStakesInfo = LIFOInfo<Version, LIFOUserStakesCapacity>;

impl IsVersionMatched for LIFOUserStakesInfo {
    fn is_version_matched(&self) -> bool {
        self.tag.is_version_matched()
    }
}

impl IsInitialized for LIFOUserStakesInfo {
    fn is_initialized(&self) -> bool {
        self.tag.is_initialized()
    }
}

pub type LIFOUserStakes<'a> = LIFO<'a, Version, UserStake, LIFOUserStakesInfo>;

pub type FIFOUserStakesInfo = FIFOInfo<Version, FIFOUserStakesCapacity>;

impl IsVersionMatched for FIFOUserStakesInfo {
    fn is_version_matched(&self) -> bool {
        self.tag.is_version_matched()
    }
}

impl IsInitialized for FIFOUserStakesInfo {
    fn is_initialized(&self) -> bool {
        self.tag.is_initialized()
    }
}

pub type FIFOUserStakes<'a> = FIFO<'a, Version, UserStake, FIFOUserStakesInfo>;

pub const SAFE_PROTECT: usize = 50;

const MAX_LP_QUEUE_NUM: usize = 3;

const MAX_PRIORITY_QUEUE_NUM: usize = 3;

const MAX_PENDING_QUEUE_NUM: usize = 3;

#[derive(Debug, Clone, Copy, Default, PartialEq, BorshSerialize, BorshDeserialize)]
pub struct QueuePoolInfo {
    pub total_pending: u64,
    pub lp_queue_num: u8,
    pub lp_queue_keys: [Pubkey; MAX_LP_QUEUE_NUM],
    pub priority_queue_num: u8,
    pub priority_queue_keys: [Pubkey; MAX_PRIORITY_QUEUE_NUM],
    pub pending_queue_num: u8,
    pub pending_queue_keys: [Pubkey; MAX_PRIORITY_QUEUE_NUM],
}

impl QueuePoolInfo {
    pub fn new(
        lp_queue_keys: &[Pubkey],
        priority_queue_keys: &[Pubkey],
        pending_queue_keys: &[Pubkey],
    ) -> Result<Self, ProgramError> {
        if lp_queue_keys.len() > MAX_LP_QUEUE_NUM {
            msg!("LP queue len is {:?}", lp_queue_keys.len());
            return Err(SilError::ExceedsMaxQueueNum.into());
        }
        
        if priority_queue_keys.len() > MAX_PRIORITY_QUEUE_NUM {
            msg!("Priority queue len is {:?}", lp_queue_keys.len());
            return Err(SilError::ExceedsMaxQueueNum.into());
        }
        if pending_queue_keys.len() > MAX_PENDING_QUEUE_NUM {
            msg!("Pending queue len is {:?}", lp_queue_keys.len());
            return Err(SilError::ExceedsMaxQueueNum.into());
        }

        let mut qpi = Self {
            total_pending: 0,
            lp_queue_num: lp_queue_keys.len() as u8,
            lp_queue_keys: Default::default(),
            priority_queue_num: priority_queue_keys.len() as u8,
            priority_queue_keys: Default::default(),
            pending_queue_num: pending_queue_keys.len() as u8,
            pending_queue_keys: Default::default(),
        };
        qpi.lp_queue_keys.copy_from_slice(&lp_queue_keys);
        qpi.priority_queue_keys.copy_from_slice(&priority_queue_keys);
        qpi.pending_queue_keys.copy_from_slice(&pending_queue_keys);

        Ok(qpi)
    }
}

impl QueuePoolInfo {
    pub fn add_pending(&mut self, pending: u64) -> ProgramResult {
        self.total_pending = self.total_pending
            .checked_add(pending)
            .ok_or(SilError::MathOverflow)?;

        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, BorshSerialize, BorshDeserialize)]
pub struct MatchPair {
    pub version: Version,
    pub admin: Pubkey,
    pub pair_round: u64,
    pub min_mint_token_0: u64,
    pub min_mint_token_1: u64,
    pub queue_pool_0: QueuePoolInfo,
    pub queue_pool_1: QueuePoolInfo,
}

impl MatchPair {
    pub fn new(
        admin: Pubkey,
        min_mint_token_0: u64,
        min_mint_token_1: u64,
        queue_pool_0: QueuePoolInfo,
        queue_pool_1: QueuePoolInfo,
    ) -> Self {
        Self {
            version: Default::default(),
            admin,
            pair_round: 0,
            min_mint_token_0,
            min_mint_token_1,
            queue_pool_0,
            queue_pool_1,
        }
    }

    pub fn add_lp_queue_key<IsFirst: Bit>(&mut self, key: Pubkey) -> ProgramResult {
        assert_ne!(key, Pubkey::default(), "Invalid LP queue pubkey");

        if IsFirst::BOOL {
            if self.queue_pool_0.lp_queue_num as usize >= MAX_LP_QUEUE_NUM {
                msg!("LP queue 0 len is {:?}", self.queue_pool_0.lp_queue_num);
                return Err(SilError::ExceedsMaxQueueNum.into());
            }

            self.queue_pool_0.lp_queue_keys[self.queue_pool_0.lp_queue_num as usize] = key;
            self.queue_pool_0.lp_queue_num += 1;

            Ok(())
        } else {
            if self.queue_pool_1.lp_queue_num as usize >= MAX_LP_QUEUE_NUM {
                msg!("LP queue 1 len is {:?}", self.queue_pool_1.lp_queue_num);
                return Err(SilError::ExceedsMaxQueueNum.into());
            }
            
            self.queue_pool_1.lp_queue_keys[self.queue_pool_1.lp_queue_num as usize] = key;
            self.queue_pool_1.lp_queue_num += 1;

            Ok(())
        }
    }

    pub fn add_priority_queue_key<IsFirst: Bit>(&mut self, key: Pubkey) -> ProgramResult {
        assert_ne!(key, Pubkey::default(), "Invalid priority queue pubkey");

        if IsFirst::BOOL {
            if self.queue_pool_0.priority_queue_num as usize >= MAX_LP_QUEUE_NUM {
                msg!("Priority queue 0 len is {:?}", self.queue_pool_0.priority_queue_num);
                return Err(SilError::ExceedsMaxQueueNum.into());
            }

            self.queue_pool_0.priority_queue_keys[self.queue_pool_0.priority_queue_num as usize] = key;
            self.queue_pool_0.priority_queue_num += 1;

            Ok(())
        } else {
            if self.queue_pool_1.priority_queue_num as usize >= MAX_LP_QUEUE_NUM {
                msg!("Priority queue 1 len is {:?}", self.queue_pool_1.priority_queue_num);
                return Err(SilError::ExceedsMaxQueueNum.into());
            }
            
            self.queue_pool_1.priority_queue_keys[self.queue_pool_1.priority_queue_num as usize] = key;
            self.queue_pool_1.priority_queue_num += 1;

            Ok(())
        }
    }

    pub fn add_pending_queue_key<IsFirst: Bit>(&mut self, key: Pubkey) -> ProgramResult {
        assert_ne!(key, Pubkey::default(), "Invalid pending queue pubkey");

        if IsFirst::BOOL {
            if self.queue_pool_0.pending_queue_num as usize >= MAX_LP_QUEUE_NUM {
                msg!("Pending queue 0 len is {:?}", self.queue_pool_0.pending_queue_num);
                return Err(SilError::ExceedsMaxQueueNum.into());
            }

            self.queue_pool_0.pending_queue_keys[self.queue_pool_0.pending_queue_num as usize] = key;
            self.queue_pool_0.pending_queue_num += 1;

            Ok(())
        } else {
            if self.queue_pool_1.pending_queue_num as usize >= MAX_LP_QUEUE_NUM {
                msg!("Pending queue 1 len is {:?}", self.queue_pool_1.pending_queue_num);
                return Err(SilError::ExceedsMaxQueueNum.into());
            }
            
            self.queue_pool_1.pending_queue_keys[self.queue_pool_1.pending_queue_num as usize] = key;
            self.queue_pool_1.pending_queue_num += 1;

            Ok(())
        }
    }
}

impl IsInitialized for MatchPair {
    fn is_initialized(&self) -> bool {
        self.version.is_initialized()
    }
}

impl IsVersionMatched for MatchPair {
    fn is_version_matched(&self) -> bool {
        self.version.is_version_matched()
    }
}

impl Packer for MatchPair {
    const LEN: usize = Version::LEN
        + std::mem::size_of::<Pubkey>()
        + std::mem::size_of::<u64>() * 3
        + std::mem::size_of::<QueuePoolInfo>() * 2;
}