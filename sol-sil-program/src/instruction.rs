#![allow(missing_docs)]
use std::{convert::TryInto, mem::size_of};
use solana_program::{
    msg,
    program_error::ProgramError,
};
use num_derive::{FromPrimitive, ToPrimitive};
use num_traits::{FromPrimitive, ToPrimitive};
use crate::error::SilError;

#[derive(Debug, Clone, Copy, FromPrimitive, ToPrimitive)]
pub enum QueueType {
    LP,
    Priority,
    Pending,
}

impl From<u8> for QueueType {
    fn from(val: u8) -> Self {
        Self::from_u8(val).expect("Queue type cannot be derived from u8")
    }
}

impl From<QueueType> for u8 {
    fn from(val: QueueType) -> Self {
        val.to_u8().expect("Queue type cannot be convert into u8")
    }
}

pub enum SilInstruction {
    /// 0
    InitAdmin,
    /// 1
    InitQueue0(QueueType),
    /// 2
    InitQueue1(QueueType),
    /// 3
    InitMatchPair(u64, u64),
    /// 4
    InitUserIndex0,
    /// 5
    InitUserIndex1,
    /// 6
    Stake(bool, u64),
    /// 7
    Untake(u64, u64),
}

impl SilInstruction {
    pub fn unpack(input: &[u8]) -> Result<Self, ProgramError> {
        let (&tag, rest) = input
            .split_first()
            .ok_or(SilError::InstructionUnpackError)?;
        
        Ok(match tag {
            0 => Self::InitAdmin,
            1 => {
                let (queue_type, _rest) = Self::unpack_queue_type(rest)?;
                Self::InitQueue0(queue_type)
            }
            2 => {
                let (queue_type, _rest) = Self::unpack_queue_type(rest)?;
                Self::InitQueue1(queue_type)
            }
            3 => {
                let (min_mint_token_0, rest) = Self::unpack_u64(rest)?;
                let (min_mint_token_1, _rest) = Self::unpack_u64(rest)?;
                Self::InitMatchPair(min_mint_token_0, min_mint_token_1)
            }
            4 => Self::InitUserIndex0,
            5 => Self::InitUserIndex1,
            6 => {
                let (is_first, rest) = Self::unpack_bool(rest)?;
                let (amount, _rest) = Self::unpack_u64(rest)?;
                Self::Stake(is_first, amount)
            }
            7 => {
                let (index, rest) = Self::unpack_u64(rest)?;
                let (amount, _rest) = Self::unpack_u64(rest)?;
                Self::Untake(index, amount)
            }
            _ => {
                return Err(SilError::InstructionUnpackError.into());
            }
        })
    }

    fn unpack_queue_type(input: &[u8]) -> Result<(QueueType, &[u8]), ProgramError> {
        if input.is_empty() {
            msg!("Queue type cannot be unpacked");
            return Err(SilError::InstructionUnpackError.into());
        }
        let (amount, rest) = input.split_first().ok_or(SilError::InstructionUnpackError)?;

        Ok((QueueType::from(*amount), rest))
    }

    fn unpack_bool(input: &[u8]) -> Result<(bool, &[u8]), ProgramError> {
        if input.is_empty() {
            msg!("bool cannot be unpacked");
            return Err(SilError::InstructionUnpackError.into());
        }
        let (amount, rest) = input.split_first().ok_or(SilError::InstructionUnpackError)?;
        match *amount {
            0 => Ok((false, rest)),
            1 => Ok((true, rest)),
            _ => {
                msg!("Boolean cannot be unpacked");
                Err(SilError::InstructionUnpackError.into())
            }
        }
    }

    fn unpack_u64(input: &[u8]) -> Result<(u64, &[u8]), ProgramError> {
        if input.len() < 8 {
            msg!("u64 cannot be unpacked");
            return Err(SilError::InstructionUnpackError.into());
        }
        let (amount, rest) = input.split_at(8);
        let amount = amount
            .get(..8)
            .and_then(|slice| slice.try_into().ok())
            .map(u64::from_le_bytes)
            .ok_or(SilError::InstructionUnpackError)?;
        Ok((amount, rest))
    }

    /// Packs a [LendingInstruction](enum.LendingInstruction.html) into a byte buffer.
    pub fn pack(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(size_of::<Self>());
        match *self {
            Self::InitAdmin => buf.push(0),
            Self::InitQueue0(queue_type) => {
                buf.push(1);
                buf.extend_from_slice(&u8::from(queue_type).to_le_bytes());
            }
            Self::InitQueue1(queue_type) => {
                buf.push(2);
                buf.extend_from_slice(&u8::from(queue_type).to_le_bytes());
            }
            Self::InitMatchPair(min_mint_token_0, min_mint_token_1) => {
                buf.push(3);
                buf.extend_from_slice(&min_mint_token_0.to_le_bytes());
                buf.extend_from_slice(&min_mint_token_1.to_le_bytes());
            }
            Self::InitUserIndex0 => buf.push(4),
            Self::InitUserIndex1 => buf.push(5),
            Self::Stake(is_first, amount) => {
                buf.push(6);
                buf.extend_from_slice(&(is_first as u8).to_le_bytes());
                buf.extend_from_slice(&amount.to_le_bytes());
            },
            Self::Untake(index, amount) => {
                buf.push(7);
                buf.extend_from_slice(&index.to_le_bytes());
                buf.extend_from_slice(&amount.to_le_bytes());
            }
        }
        buf
    }
}

