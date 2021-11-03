use super::*;
use crate::error::SilError;
use std::marker::PhantomData;
use borsh::{BorshSerialize, BorshDeserialize};
use solana_program::{entrypoint::ProgramResult, program_error::ProgramError};
use typenum::Unsigned;

#[derive(Debug, Clone, Copy, Default, BorshSerialize, BorshDeserialize)]
pub struct FIFOInfo<P: Packer, C: Unsigned> {
    pub tag: P,
    pub used: u64,
    pub head: u64,
    pub tail: u64,
    pub _c: PhantomData<C>,
}

impl<P: Packer, C: Unsigned> Packer for FIFOInfo<P, C> {
    const LEN: usize = P::LEN + std::mem::size_of::<u64>() * 3;
}

#[derive(Debug)]
pub struct FIFO<'a, P: Packer, E: Packer, C: Unsigned> {
    pub info: FIFOInfo<P, C>,
    pub _data: &'a mut [u8],
    pub _e: PhantomData<E>,
}

impl<'a, P: Packer, E: Packer, C: Unsigned> FIFO<'a, P, E, C> {
    fn is_empty(&self) -> bool {
        self.info.used == 0
    }

    fn is_full(&self) -> bool {
        self.info.used >= C::U64
    }

    fn read_element(&self, index: usize) -> Result<E, ProgramError> {
        let start = FIFOInfo::<P, C>::LEN + E::LEN * index;
        let end = start + E::LEN;

        let buf = &mut self._data[start..end].as_ref();
        let a: E = BorshDeserialize::deserialize(buf)?;
        
        Ok(a)
    }

    fn write_element(&mut self, index: usize, element: E) -> ProgramResult {
        let start = FIFOInfo::<P, C>::LEN + E::LEN * index;
        let end = start + E::LEN;

        let buf = &mut self._data[start..end].as_mut();
        element.serialize(buf)?;

        Ok(())
    }

    pub fn size(&self) -> usize {
        FIFOInfo::<P, C>::LEN + E::LEN * C::USIZE
    }

    pub fn first(&self) -> Result<E, ProgramError> {
        if self.is_empty() {
            return Err(SilError::EmptyQueue.into());
        }

        self.read_element(self.info.head as usize)
    }

    pub fn push(&mut self, element: E) -> Result<Option<usize>, ProgramError> {
        if self.is_full() {
            return Ok(None);
        }

        self.info.tail = (self.info.tail + 1) % C::U64;
        let index = ((self.info.tail - 1) % C::U64) as usize;
        self.write_element(index, element)?;
        self.info.used += 1;

        Ok(Some(index))
    }

    pub fn pop(&mut self) -> Result<E, ProgramError> {
        if self.is_empty() {
            return Err(SilError::EmptyQueue.into());
        }

        let element = self.read_element(self.info.head as usize)?;
        self.info.head = (self.info.head + 1) % C::U64;
        self.info.used -= 1;

        Ok(element)
    }
}

/// 
#[derive(Debug, Clone, Copy, Default, BorshSerialize, BorshDeserialize)]
pub struct LIFOInfo<P: Packer, C: Unsigned> {
    pub tag: P,
    pub used: u64,
    pub _c: PhantomData<C>,
}

impl<P: Packer, C: Unsigned> Packer for LIFOInfo<P, C> {
    const LEN: usize = P::LEN + std::mem::size_of::<u64>();
}

#[derive(Debug)]
pub struct LIFO<'a, P: Packer, E: Packer, C: Unsigned> {
    pub info: LIFOInfo<P, C>,
    pub _data: &'a mut [u8],
    pub _e: PhantomData<E>,
}

impl<'a, P: Packer, E: Packer, C: Unsigned> LIFO<'a, P, E, C> {
    fn is_empty(&self) -> bool {
        self.info.used == 0
    }

    fn is_full(&self) -> bool {
        self.info.used >= C::U64
    }

    fn read_element(&self, index: usize) -> Result<E, ProgramError> {
        let start = LIFOInfo::<P, C>::LEN + E::LEN * index;
        let end = start + E::LEN;

        let buf = &mut self._data[start..end].as_ref();
        let a: E = BorshDeserialize::deserialize(buf)?;
        
        Ok(a)
    }

    fn write_element(&mut self, index: usize, element: E) -> ProgramResult {
        let start = LIFOInfo::<P, C>::LEN + E::LEN * index;
        let end = start + E::LEN;

        let buf = &mut self._data[start..end].as_mut();
        element.serialize(buf)?;

        Ok(())
    }

    pub fn size(&self) -> usize {
        LIFOInfo::<P, C>::LEN + E::LEN * C::USIZE
    }

    pub fn first(&self) -> Result<E, ProgramError> {
        if self.is_empty() {
            return Err(SilError::EmptyQueue.into());
        }

        self.read_element(self.info.used as usize)
    }

    pub fn push(&mut self, element: E) -> Result<Option<usize>, ProgramError> {
        if self.is_full() {
            return Ok(None);
        }

        let index = self.info.used as usize;
        self.write_element(index, element)?;
        self.info.used += 1;

        Ok(Some(index))
    }

    pub fn pop(&mut self) -> Result<E, ProgramError> {
        if self.is_empty() {
            return Err(SilError::EmptyQueue.into());
        }

        let element = self.read_element(self.info.used as usize)?;
        self.info.used -= 1;

        Ok(element)
    }
}

pub fn fifo_push<'a, P, E, U>(fifos: &mut [FIFO<'a, P, E, U>], element: E) -> Result<usize, ProgramError>
where
    P: Packer,
    E: Packer,
    U: Unsigned,
{
    for fifo in fifos.iter_mut() {
        if let Some(index) = fifo.push(element)? {
            return Ok(index);
        }
    }

    Err(SilError::ErrorPushInFIFOGroup.into())
}

pub fn fifo_pop<'a, P, E, U>(fifo: &mut FIFO<'a, P, E, U>) -> Result<E, ProgramError>
where
    P: Packer,
    E: Packer,
    U: Unsigned,
{
    fifo.pop()
}

pub fn lifo_push<'a, P, E, U>(lifos: &mut [LIFO<'a, P, E, U>], element: E) -> Result<usize, ProgramError>
where
    P: Packer,
    E: Packer,
    U: Unsigned,
{
    for lifo in lifos.iter_mut() {
        if let Some(index) = lifo.push(element)? {
            return Ok(index);
        }
    }

    Err(SilError::ErrorPushInLIFOGroup.into())
}

pub fn lifo_pop<'a, P, E, U>(lifos: &mut [LIFO<'a, P, E, U>]) -> Result<E, ProgramError>
where
    P: Packer,
    E: Packer,
    U: Unsigned,
{
    for lifo in lifos.iter_mut() {
        if lifo.is_full() {
            continue;
        } else {
           return lifo.pop();
        }
    }

    Err(SilError::ErrorPopFromFIFOGroup.into())
}
