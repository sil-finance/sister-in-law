// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2015, 2016, 2017 Dapphub
// Adapted by Ethereum Community 2020
pragma solidity 0.6.12;

interface ERC677Receiver {
    function onTokenTransfer(address, uint, bytes calldata) external;
}

interface FlashMinterLike {
    function executeOnFlashMint(uint, bytes calldata) external;
}
