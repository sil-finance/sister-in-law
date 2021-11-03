use borsh::{BorshSerialize, BorshDeserialize};
use solana_program::{program_pack::IsInitialized, pubkey::Pubkey};

use super::*;

#[derive(Debug, Clone, Copy, Default, BorshSerialize, BorshDeserialize)]
pub struct Admin {
    pub version: Version,
    pub bump_seed: u8,
    pub owner: Pubkey,
}

impl Admin {
    pub fn new(bump_seed: u8, owner: Pubkey) -> Self {
        Self {
            version: Default::default(),
            bump_seed,
            owner,
        }
    }
}

impl IsInitialized for Admin {
    fn is_initialized(&self) -> bool {
        self.version.is_initialized()
    }
}

impl IsVersionMatched for Admin {
    fn is_version_matched(&self) -> bool {
        self.version.is_version_matched()
    }
}

impl Packer for Admin {
    const LEN: usize = Version::LEN 
        + std::mem::size_of::<u8>()
        + std::mem::size_of::<Pubkey>();
}
