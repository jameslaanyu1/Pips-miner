# MetaAPI Setup - Quick Reference

## 🚀 Quick Setup (5 Minutes)

### 1. Get MetaAPI Token
```
https://metaapi.cloud → Sign Up → API Keys → Copy Token
```

### 2. Link HFM Account
```
https://app.metaapi.cloud → Accounts → Create New → HFM → Link
```

### 3. Create .env File
```bash
cat > .env << EOF
METAAPI_TOKEN=your_token_here
METAAPI_ACCOUNT_ID=your_id_here
TRADING_SYMBOL=XAUUSD
EOF
```

### 4. Test Connection
```bash
python test_metaapi_bridge.py
```

### 5. Run Bot
```bash
python metaapi_bot.py
```

---

## 📝 Credentials Format

**API Token Example:**
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

**Account ID Example:**
```
1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p
```

---

## 🔗 Important Links

| Resource | URL |
|----------|-----|
| MetaAPI Cloud | https://metaapi.cloud/ |
| MetaAPI Dashboard | https://app.metaapi.cloud/ |
| HFM Website | https://www.hfm.com/ |
| HFM Demo Account | https://www.hfm.com/open-demo-account |
| HFM Live Account | https://www.hfm.com/open-live-account |
| PIPS Miner GitHub | https://github.com/JamesLaanyu1/pips-miner |

---

## ✅ Verification Checklist

- [ ] MetaAPI account created
- [ ] API token copied
- [ ] HFM account created (demo or live)
- [ ] HFM account linked to MetaAPI
- [ ] Account ID obtained
- [ ] .env file created with credentials
- [ ] Dependencies installed (`pip install -r requirements.txt`)
- [ ] Connection test passed (`python test_metaapi_bridge.py`)
- [ ] Backend running (`python backend/app.py`)
- [ ] Bot running (`python metaapi_bot.py`)
- [ ] Mobile app connected

---

## 📞 Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| Token not working | Regenerate at MetaAPI → API Keys |
| Account not found | Check Account ID, ensure deployed |
| Connection timeout | Check internet, verify firewall |
| No candles data | Check if market is open |
| Insufficient balance | Deposit funds to HFM account |

---

## 🎯 Next Steps

1. ✅ Complete setup above
2. 📊 Run tests to verify
3. 💰 Backtest on demo account
4. 📈 Monitor live metrics
5. 🚀 Deploy to live (optional)

---

**For complete setup guide, see: [METAAPI_SETUP_GUIDE.md](METAAPI_SETUP_GUIDE.md)**
