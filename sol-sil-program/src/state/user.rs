use crate::error::SilError;
use super::*;
use borsh::{BorshSerialize, BorshDeserialize};
use solana_program::{msg, entrypoint::ProgramResult, pubkey::Pubkey, program_pack::IsInitialized};
use spl_math::precise_number::PreciseNumber;

#[derive(Debug, Clone, Copy, Default, PartialEq, BorshSerialize, BorshDeserialize)]
pub struct UserStake {
    pub token_account: Pubkey,
    pub amount: u64,
    pub per_rate: u128,
    pub lp_per_token: u64,
    pub round: u64,
}

impl Packer for UserStake {
    const LEN: usize = std::mem::size_of::<Self>();
}

const USER_LP_CAPACITY: usize = 30;
const USER_PRIORITY_CAPACITY: usize = 30;
const USER_PENDING_CAPACITY: usize = 30;

type Index = (u8, u16);

#[derive(Debug, Clone, Copy, Default, BorshSerialize, BorshDeserialize)]
pub struct UserIndex {
    pub version: Version,
    pub match_pair: Pubkey,
    pub is_first: bool,
    pub lp_num: u32,
    pub lp_index: [Index; USER_LP_CAPACITY],
    pub priority_num: u32,
    pub priority_index: [Index; USER_PRIORITY_CAPACITY],
    pub pending_num: u32,
    pub pending_index: [Index; USER_PENDING_CAPACITY],
}

impl IsInitialized for UserIndex {
    fn is_initialized(&self) -> bool {
        self.version.is_initialized()
    }
}

impl IsVersionMatched for UserIndex {
    fn is_version_matched(&self) -> bool {
        self.version.is_version_matched()
    }
}

impl Packer for UserIndex {
    const LEN: usize = Version::LEN
        + std::mem::size_of::<Pubkey>()
        + std::mem::size_of::<bool>()
        + std::mem::size_of::<u32>() * 3
        + USER_LP_CAPACITY * std::mem::size_of::<Index>()
        + USER_PRIORITY_CAPACITY * std::mem::size_of::<Index>()
        + USER_PENDING_CAPACITY * std::mem::size_of::<Index>();
}

impl UserIndex {
    pub fn push_lp(&mut self, lp_index: (u8, u16)) -> ProgramResult {
        if self.lp_num as usize >= USER_LP_CAPACITY {
            msg!("LP num {:?} exceeds capacity", self.lp_num);
            return Err(SilError::ErrorPushInUserIndex.into());
        }
        self.lp_index[self.lp_num as usize] = lp_index;
        self.lp_num += 1;

        Ok(())
    }

    pub fn pop_lp(&mut self) -> ProgramResult {
        if self.lp_num == 0 {
            msg!("LP num is zero");
            return Err(SilError::ErrorPopFromUserIndex.into());
        }
        self.lp_num -= 1;

        Ok(())
    }

    pub fn push_priority(&mut self, priority_index: (u8, u16)) -> ProgramResult {
        if self.priority_num as usize >= USER_PRIORITY_CAPACITY {
            msg!("Priority num {:?} exceeds capacity", self.lp_num);
            return Err(SilError::ErrorPushInUserIndex.into());
        }
        self.priority_index[self.lp_num as usize] = priority_index;
        self.priority_num += 1;

        Ok(())
    }

    pub fn pop_priority(&mut self) -> ProgramResult {
        if self.priority_num == 0 {
            msg!("Priority num is zero");
            return Err(SilError::ErrorPopFromUserIndex.into());
        }
        self.priority_num -= 1;

        Ok(())
    }

    pub fn push_pending(&mut self, pending_index: (u8, u16)) -> ProgramResult {
        if self.pending_num as usize >= USER_PENDING_CAPACITY {
            msg!("Pending num {:?} exceeds capacity", self.lp_num);
            return Err(SilError::ErrorPushInUserIndex.into());
        }
        self.pending_index[self.lp_num as usize] = pending_index;
        self.pending_num += 1;

        Ok(())
    }

    pub fn pop_pending(&mut self) -> ProgramResult {
        if self.pending_num == 0 {
            msg!("Pending num is zero");
            return Err(SilError::ErrorPopFromUserIndex.into());
        }
        self.pending_num -= 1;

        Ok(())
    }
}

pub struct UserAmount {
    pub account: Pubkey,
    pub amount: u64,
}

pub struct RequestWrapper {
    pub index: usize,
    pub account: Pubkey,
    pub amount: u64,
    pub rate: u128,
    pub rate2: u128,
}