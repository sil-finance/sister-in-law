mod admin;
mod queue;
mod match_pair;
mod user;

pub use admin::*;
pub use queue::*;
pub use match_pair::*;
pub use user::*;

use borsh::{BorshSerialize, BorshDeserialize};
use solana_program::program_pack::IsInitialized;

pub trait Packer: Copy + Default + BorshSerialize + BorshDeserialize {
    const LEN: usize;
}

pub trait IsVersionMatched {
    fn is_version_matched(&self) -> bool;
}

pub const PROGRAM_VERSION: u8 = 1;

#[derive(Debug, Clone, Copy, BorshSerialize, BorshDeserialize)]
pub struct Version(u8);

impl Default for Version {
    fn default() -> Self {
        Self(PROGRAM_VERSION)
    }
}

impl IsInitialized for Version {
    fn is_initialized(&self) -> bool {
        self.0 > 0
    }
}

impl IsVersionMatched for Version {
    fn is_version_matched(&self) -> bool {
        self.0 == PROGRAM_VERSION
    }
}

const PADDING_LEN: usize = 128;

impl Packer for Version {
    const LEN: usize = std::mem::size_of::<Self>() + PADDING_LEN;
}