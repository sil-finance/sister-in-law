//! Program state processor
use crate::{error::SilError, helper::*, instruction::{QueueType, SilInstruction},
    state::{Admin, MatchPair, LIFOUserStakesInfo, FIFOUserStakesInfo}};
use borsh::{BorshDeserialize, BorshSerialize};
use num_traits::FromPrimitive;
use solana_program::{
    account_info::{AccountInfo, next_account_info},
    decode_error::DecodeError,
    entrypoint::ProgramResult,
    instruction::{AccountMeta, Instruction},
    msg,
    program::{invoke, invoke_signed},
    program_error::{PrintProgramError, ProgramError},
    program_option::COption,
    program_pack::{IsInitialized, Pack},
    pubkey::Pubkey,
    sysvar::{clock::Clock, rent::Rent, Sysvar},
};
use spl_token::{state::{Mint, Account}, native_mint};
use typenum::{Bit, True, False};

fn process_init_admin(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    // 1
    let rent = &Rent::from_account_info(next_account_info(account_info_iter)?)?;
    // 2
    let admin_info = next_account_info(account_info_iter)?;
    if admin_info.owner != program_id {
        msg!("Admin provided is not owned by the sil program");
        return Err(SilError::InvalidAccountOwner.into());
    }
    assert_rent_exempt(rent, admin_info)?;
    assert_uninitialized::<Admin>(admin_info)?;
    // 3
    let authority_info = next_account_info(account_info_iter)?;
    if !authority_info.is_signer {
        msg!("authority is not a signer");
        return Err(SilError::InvalidAuthority.into());
    }

    let admin = Admin::new(
        Pubkey::find_program_address(&[admin_info.key.as_ref()], program_id).1,
        *authority_info.key,
    );
    admin.serialize(&mut admin_info.try_borrow_mut_data()?.as_mut())?;

    Ok(())
}

fn process_init_queue<IsFirst: Bit>(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    queue_type: QueueType,
) -> ProgramResult {
    let account_info_iter = &mut accounts.iter();
    // 1
    let rent = &Rent::from_account_info(next_account_info(account_info_iter)?)?;
    // 2
    let admin_info = next_account_info(account_info_iter)?;
    if admin_info.owner != program_id {
        msg!("Admin provided is not owned by the sil program");
        return Err(SilError::InvalidAccountOwner.into());
    }
    let admin = unpack_account::<Admin>(admin_info)?;
    // 3
    let match_pair_info = next_account_info(account_info_iter)?;
    if match_pair_info.owner != program_id {
        msg!("Match Pair provided is not owned by the sil program");
        return Err(SilError::InvalidAccountOwner.into());
    }
    let mut match_pair = unpack_account::<MatchPair>(match_pair_info)?;
    if &match_pair.admin != admin_info.key {
        msg!("Admin in match pair is not matched admin info provided");
        return Err(SilError::InvalidMatchPair.into());
    }
    // 4
    let authority_info = next_account_info(account_info_iter)?;
    if authority_info.key != &admin.owner {
        msg!("Only Admin owner can create Match Pair");
        return Err(SilError::InvalidAuthority.into());
    }
    if !authority_info.is_signer {
        msg!("authority is not a signer");
        return Err(SilError::InvalidAuthority.into());
    }
    // 5
    let queue_info = next_account_info(account_info_iter)?;
    assert_rent_exempt(rent, queue_info)?;
    match queue_type {
        QueueType::LP => {
            assert_uninitialized::<LIFOUserStakesInfo>(queue_info)?;
            match_pair.add_lp_queue_key::<IsFirst>(*queue_info.key);
            LIFOUserStakesInfo::default().serialize(&mut queue_info.try_borrow_mut_data()?.as_mut())?;
        }
        QueueType::Priority => {
            assert_uninitialized::<FIFOUserStakesInfo>(queue_info)?;
            match_pair.add_priority_queue_key::<IsFirst>(*queue_info.key);
            FIFOUserStakesInfo::default().serialize(&mut queue_info.try_borrow_mut_data()?.as_mut())?;
        }
        QueueType::Pending => {
            assert_uninitialized::<FIFOUserStakesInfo>(queue_info)?;
            match_pair.add_pending_queue_key::<IsFirst>(*queue_info.key);
            FIFOUserStakesInfo::default().serialize(&mut queue_info.try_borrow_mut_data()?.as_mut())?;
        }
    }
    match_pair.serialize(&mut match_pair_info.try_borrow_mut_data()?.as_mut())?;
    
    Ok(())
}