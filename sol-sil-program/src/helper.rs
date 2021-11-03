use std::marker::PhantomData;
use typenum::{U1, U9};
use solana_program::{
    account_info::AccountInfo,
    entrypoint::ProgramResult,
    instruction::{Instruction, AccountMeta},
    program::{invoke, invoke_signed},
    msg,
    sysvar::rent::Rent,
    program_error::ProgramError,
    program_pack::IsInitialized,
};
use crate::{error::SilError, state::{IsVersionMatched, Packer}};

pub fn assert_rent_exempt(rent: &Rent, account_info: &AccountInfo) -> ProgramResult {
    if !rent.is_exempt(account_info.lamports(), account_info.data_len()) {
        msg!(&rent.minimum_balance(account_info.data_len()).to_string());
        Err(SilError::NotRentExempt.into())
    } else {
        Ok(())
    }
}

pub fn assert_uninitialized<T: Packer + IsInitialized>(account_info: &AccountInfo) -> ProgramResult {
    if account_info.data_len() < T::LEN {
        return Err(ProgramError::AccountDataTooSmall);
    }
    let account: T = T::deserialize(&mut account_info.try_borrow_data()?.as_ref())?;
    if account.is_initialized() {
        Err(SilError::AlreadyInitialized.into())
    } else {
        Ok(())
    }
}

pub fn unpack_account<T: Packer + IsVersionMatched>(account_info: &AccountInfo) -> Result<T, ProgramError> {
    if account_info.data_len() < T::LEN {
        return Err(ProgramError::AccountDataTooSmall);
    }
    let account: T = T::deserialize(&mut account_info.try_borrow_data()?.as_ref())?;
    if account.is_version_matched() {
        Ok(account)
    } else {
        Err(SilError::VersionIsNotMatched.into())
    }
}

/// Invoke signed unless signers seeds are empty
#[inline(always)]
fn invoke_optionally_signed(
    instruction: &Instruction,
    account_infos: &[AccountInfo],
    authority_signer_seeds: &[&[u8]],
) -> ProgramResult {
    if authority_signer_seeds.is_empty() {
        invoke(instruction, account_infos)
    } else {
        invoke_signed(instruction, account_infos, &[authority_signer_seeds])
    }
}

/// Issue a spl_token `InitializeAccount` instruction.
#[inline(always)]
pub fn spl_token_init_account(params: TokenInitializeAccountParams<'_>) -> ProgramResult {
    let TokenInitializeAccountParams {
        account,
        mint,
        owner,
        rent,
        token_program,
    } = params;
    let ix = spl_token::instruction::initialize_account(
        token_program.key,
        account.key,
        mint.key,
        owner.key,
    )?;
    let result = invoke(&ix, &[account, mint, owner, rent, token_program]);
    result.map_err(|_| SilError::TokenInitializeAccountFailed.into())
}

/// Issue a spl_token `Transfer` instruction.
#[inline(always)]
pub fn spl_token_transfer(params: TokenTransferParams<'_, '_>) -> ProgramResult {
    let TokenTransferParams {
        source,
        destination,
        authority,
        token_program,
        amount,
        authority_signer_seeds,
    } = params;
    let result = invoke_optionally_signed(
        &spl_token::instruction::transfer(
            token_program.key,
            source.key,
            destination.key,
            authority.key,
            &[],
            amount,
        )?,
        &[source, destination, authority, token_program],
        authority_signer_seeds,
    );
    result.map_err(|_| SilError::TokenTransferFailed.into())
}

/// Issue a spl_token `Approve` instruction.
#[inline(always)]
pub fn spl_token_approve(params: TokenApproveParams<'_, '_>) -> ProgramResult {
    let TokenApproveParams {
        source,
        delegate,
        authority,
        token_program,
        amount,
        authority_signer_seeds,
    } = params;
    let result = invoke_optionally_signed(
        &spl_token::instruction::approve(
            token_program.key,
            source.key,
            delegate.key,
            authority.key,
            &[],
            amount,
        )?,
        &[source, delegate, authority, token_program],
        authority_signer_seeds,
    );
    result.map_err(|_| SilError::TokenApproveFailed.into())
}

/// Issue a spl_token `Revoke` instruction.
#[inline(always)]
pub fn spl_token_revoke(params: TokenRevokeParams<'_, '_>) -> ProgramResult {
    let TokenRevokeParams {
        source,
        authority,
        token_program,
        authority_signer_seeds,
    } = params;
    let result = invoke_optionally_signed(
        &spl_token::instruction::revoke(
            token_program.key,
            source.key,
            authority.key,
            &[],
        )?,
        &[source, authority, token_program],
        authority_signer_seeds,
    );
    result.map_err(|_| SilError::TokenRevokeFailed.into())
}

pub struct TokenInitializeAccountParams<'a> {
    pub account: AccountInfo<'a>,
    pub mint: AccountInfo<'a>,
    pub owner: AccountInfo<'a>,
    pub rent: AccountInfo<'a>,
    pub token_program: AccountInfo<'a>,
}

pub struct TokenTransferParams<'a: 'b, 'b> {
    pub source: AccountInfo<'a>,
    pub destination: AccountInfo<'a>,
    pub amount: u64,
    pub authority: AccountInfo<'a>,
    pub authority_signer_seeds: &'b [&'b [u8]],
    pub token_program: AccountInfo<'a>,
}

pub struct TokenApproveParams<'a: 'b, 'b> {
    pub source: AccountInfo<'a>,
    pub delegate: AccountInfo<'a>,
    pub amount: u64,
    pub authority: AccountInfo<'a>,
    pub authority_signer_seeds: &'b [&'b [u8]],
    pub token_program: AccountInfo<'a>,
}

pub struct TokenRevokeParams<'a: 'b, 'b> {
    pub source: AccountInfo<'a>,
    pub authority: AccountInfo<'a>,
    pub authority_signer_seeds: &'b [&'b [u8]],
    pub token_program: AccountInfo<'a>,
}

pub trait Data: Sized {
    fn to_vec(self) -> Vec<u8>;
}

pub fn invoke_swap<'a, D: Data>(
    data: D,
    swap_program_info: &AccountInfo<'a>,
    mut account_infos: Vec<AccountInfo<'a>>,
    signer_seeds: &[&[u8]],
) -> ProgramResult {
    let instruction_accounts = account_infos
        .iter()
        .map(|account_info| {
            AccountMeta {
                pubkey: *account_info.key,
                is_signer: account_info.is_signer,
                is_writable: account_info.is_writable,
            }
        }).collect::<Vec<_>>();
        account_infos.push(swap_program_info.clone());

    invoke_signed(
        &Instruction {
            program_id: *swap_program_info.key,
            accounts: instruction_accounts,
            data: data.to_vec(),
        },
        &account_infos,
        &[signer_seeds],
    )
}

pub enum Swap {
    Solana,
    Raydium,
    Saber,
}

pub type OfficialSwapTag = U1;
pub type SaberSwapTag = U1;
pub type RaydiumSwapTag = U9;

#[derive(Clone, Debug, PartialEq)]
pub struct SwapData<T: typenum::Unsigned> {
    /// SOURCE amount to transfer, output to DESTINATION is based on the exchange rate
    pub amount_in: u64,
    /// Minimum amount of DESTINATION token to output, prevents excessive slippage
    pub minimum_amount_out: u64,
    /// maker for tag
    pub _t: PhantomData<T>,
}

impl<T: typenum::Unsigned> Data for SwapData<T> {
    fn to_vec(self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(1 + 8 + 8);
        buf.push(T::U8);
        buf.extend_from_slice(&self.amount_in.to_le_bytes());
        buf.extend_from_slice(&self.minimum_amount_out.to_le_bytes());

        buf
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct OfficialDepositData {
    /// Pool token amount to transfer. token_a and token_b amount are set by
    /// the current exchange rate and size of the pool
    pub pool_token_amount: u64,
    /// Maximum token A amount to deposit, prevents excessive slippage
    pub maximum_token_a_amount: u64,
    /// Maximum token B amount to deposit, prevents excessive slippage
    pub maximum_token_b_amount: u64,
}

impl Data for OfficialDepositData {
    fn to_vec(self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(1 + 8 + 8 + 8);
        buf.push(2);
        buf.extend_from_slice(&self.pool_token_amount.to_le_bytes());
        buf.extend_from_slice(&self.maximum_token_a_amount.to_le_bytes());
        buf.extend_from_slice(&self.maximum_token_b_amount.to_le_bytes());

        buf
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct SaberDepositData {
    /// Token A amount to deposit
    pub token_a_amount: u64,
    /// Token B amount to deposit
    pub token_b_amount: u64,
    /// Minimum LP tokens to mint, prevents excessive slippage
    pub min_mint_amount: u64,
}

impl Data for SaberDepositData {
    fn to_vec(self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(1 + 8 + 8 + 8);
        buf.push(2);
        buf.extend_from_slice(&self.token_a_amount.to_le_bytes());
        buf.extend_from_slice(&self.token_b_amount.to_le_bytes());
        buf.extend_from_slice(&self.min_mint_amount.to_le_bytes());

        buf
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RaydiumDepositData {
    /// Pool token amount to transfer. token_a and token_b amount are set by
    /// the current exchange rate and size of the pool
    pub max_coin_amount: u64,
    pub max_pc_amount: u64,
    pub base_side: u64,
}

impl Data for RaydiumDepositData {
    fn to_vec(self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(1 + 8 + 8 + 8);
        buf.push(3);
        buf.extend_from_slice(&self.max_coin_amount.to_le_bytes());
        buf.extend_from_slice(&self.max_pc_amount.to_le_bytes());
        buf.extend_from_slice(&self.base_side.to_le_bytes());

        buf
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct OfficialWithdrawData {
    /// Amount of pool tokens to burn. User receives an output of token a
    /// and b based on the percentage of the pool tokens that are returned.
    pub pool_token_amount: u64,
    /// Minimum amount of token A to receive, prevents excessive slippage
    pub minimum_token_a_amount: u64,
    /// Minimum amount of token B to receive, prevents excessive slippage
    pub minimum_token_b_amount: u64,
}

impl Data for OfficialWithdrawData {
    fn to_vec(self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(1 + 8 + 8 + 8);
        buf.push(3);
        buf.extend_from_slice(&self.pool_token_amount.to_le_bytes());
        buf.extend_from_slice(&self.minimum_token_a_amount.to_le_bytes());
        buf.extend_from_slice(&self.minimum_token_b_amount.to_le_bytes());

        buf
    }
}

pub type SaberWithdrawData = OfficialWithdrawData;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct RaydiumWithdrawData {
    /// Pool token amount to transfer. token_a and token_b amount are set by
    /// the current exchange rate and size of the pool
    pub amount: u64,
}

impl Data for RaydiumWithdrawData {
    fn to_vec(self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(1 + 8);
        buf.push(4);
        buf.extend_from_slice(&self.amount.to_le_bytes());

        buf
    }
}
