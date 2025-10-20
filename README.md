# 🛑🔐 Emergency Wallet Freeze Smart Contract

## 📌 Overview

The **Emergency Wallet Freeze** contract is a security-focused smart contract wallet that allows users to protect their crypto assets by assigning **trusted guardians**.  
If the wallet owner’s keys are compromised or the account is under attack, guardians can **vote to freeze** the wallet, blocking withdrawals until the situation is resolved.

This adds a **social recovery + emergency pause layer** on top of standard crypto wallets, offering additional protection against hacks, phishing, and theft.
   
---   
       
## ⚡ What is it?    
       
A **smart contract wallet** with built-in freeze functionality:  

- The **Owner** controls the wallet and funds under normal conditions.
- **Guardians** are pre-approved trusted addresses (friends, family, or institutions).
- If a security risk is detected, guardians can **vote to freeze**.
- When enough guardian votes are cast (`requiredConfirmations`), the wallet enters a **frozen state**.
- While frozen, no funds can be withdrawn or transferred.
- The **Owner** can unfreeze early, or the wallet will **auto-unfreeze** after a set `freezeDuration`.

---

## 🎯 Why this matters

- **Crypto hacks are common:** Private keys can be leaked, wallets drained in seconds.
- **No safety net in EOAs:** Traditional wallets (EOA like MetaMask) have no built-in recovery or freeze feature.
- **User-friendly security:** Assigning guardians (friends/family) provides a human safety net.
- **Balances decentralization & safety:** Owner maintains control, but guardians can intervene in emergencies.

This contract provides an **extra layer of defense** without needing to trust centralized services.

---

## 🔑 Key Features

- **Guardian Assignment:** Owner can add/remove guardians at any time.
- **Freeze Vote System:** Guardians vote to freeze; freeze activates once votes ≥ threshold.
- **Auto-Unfreeze:** After `freezeDuration`, contract automatically unfreezes.
- **Owner Unfreeze:** Owner can unfreeze manually once secure.
- **Multi-Guardian Security:** Require majority confirmation for freeze activation.
- **Asset Management:**
  - Store and withdraw ETH.
  - Store and withdraw ERC-20 tokens.
  - Execute arbitrary calls (DeFi, dApps, etc.), blocked when frozen.

---

## 🛠️ Use Cases

1. **Personal Security:**  
   Protect funds in case of phishing or private key leak.

2. **Family / Social Recovery:**  
   Beginner crypto users can appoint family/friends to safeguard their funds.

3. **Institutional Accounts:**  
   Company wallets can have multiple managers with freeze authority.

4. **Inheritance Planning:**  
   Guardians can act as recovery agents if the owner loses access.

---

## ⚙️ How it Works

1. **Setup:**

   - Deploy the wallet with an initial set of guardians.
   - Define `requiredConfirmations` (e.g., 2 out of 3 guardians) and `freezeDuration` (e.g., 24 hours).

2. **Normal Operation:**

   - Owner deposits ETH/ERC-20 tokens.
   - Owner withdraws or interacts with dApps normally.

3. **Freeze Process:**

   - Guardians detect compromise.
   - Each guardian calls `guardianVoteToFreeze()`.
   - Once enough votes are collected, contract sets `freezeUntil = now + freezeDuration`.
   - Withdrawals/executes are blocked.

4. **Unfreeze:**
   - Owner can call `ownerUnfreeze()` after securing account.
   - Or wait for auto-expiry → contract unfreezes automatically.

---

## 🔒 Security Notes

- This contract **cannot freeze arbitrary wallets**. Users must deposit funds into this wallet to use the freeze functionality.
- Guardians must be **carefully chosen** (trusted individuals/entities).
- A compromised guardian cannot steal funds but can **initiate freeze votes**.
- Freeze/unfreeze logic is transparent on-chain.

---

## 📄 License

MIT License. Free to use, modify, and integrate.

---
