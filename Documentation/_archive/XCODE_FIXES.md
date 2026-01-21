# Xcode Compilation Fixes

## Summary
Fixed 2 compilation errors in the Nexus iOS app.

---

## Fix 1: FinanceViewModel.swift - Line 167
**Error**: `Extraneous argument label 'merchantName:' in call`

**Root Cause**:
The function `addTransaction` uses `_` for the first parameter, meaning it should be called without a label.

**Location**: `/Users/rafa/Cyber/Dev/Nexus-mobile/Nexus/ViewModels/FinanceViewModel.swift:167`

**Changed From**:
```swift
let response = try await api.addTransaction(
    merchantName: merchantName,  // ❌ Incorrect - has label
    amount: amount,
    category: category,
    notes: notes
)
```

**Changed To**:
```swift
let response = try await api.addTransaction(
    merchantName,  // ✅ Correct - no label
    amount: amount,
    category: category,
    notes: notes
)
```

**Function Signature** (from NexusAPI.swift:45):
```swift
func addTransaction(_ merchantName: String, amount: Double, category: String? = nil, notes: String? = nil)
```

---

## Fix 2: FinanceView.swift - Line 329
**Error**: `Trailing closure passed to parameter of type 'Predicate<Transaction>' that does not accept a closure`

**Root Cause**:
Swift compiler confused array's `filter` method with SwiftData's Predicate-based filtering. Also, tuple type mismatch between named and unnamed tuple elements.

**Location**: `/Users/rafa/Cyber/Dev/Nexus-mobile/Nexus/Views/Finance/FinanceView.swift:321-352`

**Solution**:
1. Replaced `filter` with `compactMap` to avoid SwiftData Predicate ambiguity
2. Fixed tuple to use named elements: `(start: customStartDate, end: customEndDate)`
3. Rewrote filtering logic using guard statements and early returns

**Changed From**:
```swift
private var filteredTransactions: [Transaction] {
    var filtered = viewModel.recentTransactions

    // Date range filter
    let dateRange = selectedDateRange == .custom ?
        (customStartDate, customEndDate) :  // ❌ Unnamed tuple
        selectedDateRange.getDateRange()

    filtered = filtered.filter { transaction in  // ❌ Conflicts with SwiftData
        transaction.date >= dateRange.start && transaction.date < dateRange.end
    }

    // Search filter
    if !searchText.isEmpty {
        filtered = filtered.filter { transaction in
            transaction.merchantName.localizedCaseInsensitiveContains(searchText) ||
            (transaction.category?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (transaction.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // Category filter
    if let category = selectedCategory {
        filtered = filtered.filter { $0.category == category }
    }

    return filtered
}
```

**Changed To**:
```swift
private var filteredTransactions: [Transaction] {
    let dateRange = selectedDateRange == .custom ?
        (start: customStartDate, end: customEndDate) :  // ✅ Named tuple elements
        selectedDateRange.getDateRange()

    return viewModel.recentTransactions.compactMap { transaction -> Transaction? in  // ✅ Uses compactMap
        // Date range filter
        guard transaction.date >= dateRange.start && transaction.date < dateRange.end else {
            return nil
        }

        // Search filter
        if !searchText.isEmpty {
            let matchesMerchant = transaction.merchantName.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = transaction.category?.localizedCaseInsensitiveContains(searchText) ?? false
            let matchesNotes = transaction.notes?.localizedCaseInsensitiveContains(searchText) ?? false

            guard matchesMerchant || matchesCategory || matchesNotes else {
                return nil
            }
        }

        // Category filter
        if let category = selectedCategory {
            guard transaction.category == category else {
                return nil
            }
        }

        return transaction
    }
}
```

**Why compactMap works**:
- SwiftData doesn't override `compactMap`, only `filter`
- Same filtering logic: nil = excluded, non-nil = included
- More explicit about transformation intention
- No ambiguity with Predicate types

---

## Build Instructions

### From Terminal (Requires Xcode Developer Tools)
```bash
# Switch to Xcode developer directory (requires sudo)
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

# Build from terminal
cd /Users/rafa/Cyber/Dev/Nexus-mobile
xcodebuild -scheme Nexus -configuration Debug -sdk iphoneos
```

### From Xcode GUI (Recommended)
1. Open `/Users/rafa/Cyber/Dev/Nexus-mobile/Nexus.xcodeproj` in Xcode
2. Select target device/simulator
3. Press ⌘+B (Command+B) to build
4. Build should succeed without errors

---

## Files Modified

1. `/Users/rafa/Cyber/Dev/Nexus-mobile/Nexus/ViewModels/FinanceViewModel.swift`
   - Line 168: Removed `merchantName:` label

2. `/Users/rafa/Cyber/Dev/Nexus-mobile/Nexus/Views/Finance/FinanceView.swift`
   - Lines 321-352: Rewrote `filteredTransactions` computed property
   - Changed from `filter` to `compactMap`
   - Fixed tuple naming
   - Improved readability with guard statements

---

## Testing Checklist

After building successfully:

- [ ] Test adding manual transaction
- [ ] Test filtering transactions by date range
- [ ] Test searching transactions by merchant name
- [ ] Test filtering by category
- [ ] Test date range picker (custom dates)
- [ ] Verify all filters work together

---

## Notes

- The xcodebuild tool requires full Xcode installation, not just Command Line Tools
- Current developer directory: `/Library/Developer/CommandLineTools` (insufficient)
- Required developer directory: `/Applications/Xcode.app/Contents/Developer`
- Claude Code CLI cannot run `sudo` commands due to password requirement
- Build from Xcode GUI instead for immediate verification

---

**Status**: Code fixes applied ✅
**Build Verification**: Requires Xcode GUI or sudo access
**Next Step**: Open in Xcode and build (⌘+B)
