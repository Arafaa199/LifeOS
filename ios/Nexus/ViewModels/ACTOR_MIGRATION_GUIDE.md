# Actor Migration Guide - OfflineQueue

## What Changed?

`OfflineQueue` was converted from a `class` with manual locks to an `actor` for better thread safety. This means all interactions with `OfflineQueue` must now be `async`.

## Common Error

```
Call to actor-isolated instance method 'XXX()' in a synchronous main actor-isolated context
```

## How to Fix

### ✅ Before (Old - Synchronous)
```swift
func updateCount() {
    let count = OfflineQueue.shared.getQueueCount()
    self.queuedItems = count
}
```

### ✅ After (New - Async)
```swift
func updateCount() async {
    let count = await OfflineQueue.shared.getQueueCount()
    self.queuedItems = count
}
```

## Common Scenarios & Solutions

### 1. Calling from `init()`

**Problem:**
```swift
init() {
    updateQueueCount() // Error if method is async
}
```

**Solution:**
```swift
init() {
    // Wrap in Task for async execution
    Task {
        await updateQueueCount()
    }
}
```

### 2. Calling from SwiftUI `.onAppear`

**Problem:**
```swift
.onAppear {
    viewModel.updateCount() // Error if method is async
}
```

**Solution:**
```swift
.task {
    await viewModel.updateCount()
}
// OR
.onAppear {
    Task {
        await viewModel.updateCount()
    }
}
```

### 3. Calling from Button Actions

**Problem:**
```swift
Button("Clear Queue") {
    OfflineQueue.shared.clearQueue() // Error
}
```

**Solution:**
```swift
Button("Clear Queue") {
    Task {
        await OfflineQueue.shared.clearQueue()
    }
}
```

### 4. Enqueueing Items

Already handled in the extension, but if calling directly:

**Solution:**
```swift
Task {
    await OfflineQueue.shared.enqueue(.food(text: "lunch"), priority: .normal)
}
```

### 5. Processing Queue Manually

**Solution:**
```swift
Button("Sync Now") {
    Task {
        await OfflineQueue.shared.processQueue()
    }
}
```

## All `OfflineQueue` Methods That Need `await`

```swift
actor OfflineQueue {
    // All of these require 'await':
    func enqueue(_ request: QueuedRequest, priority: Priority = .normal) async
    func processQueue() async
    func getQueueCount() async -> Int
    func clearQueue() async
}
```

## Quick Reference

| Context | How to Call |
|---------|------------|
| In `@MainActor` ViewModel | Make method `async`, use `await` |
| In `init()` | Wrap in `Task { await ... }` |
| In SwiftUI `.onAppear` | Use `.task { await ... }` |
| In Button action | Wrap in `Task { await ... }` |
| In async function | Use `await` directly |

## Example: Full ViewModel Update

```swift
@MainActor
class MyViewModel: ObservableObject {
    @Published var queueCount = 0
    
    init() {
        // Initialize queue count asynchronously
        Task {
            await updateQueueCount()
        }
    }
    
    // Make method async
    func updateQueueCount() async {
        queueCount = await OfflineQueue.shared.getQueueCount()
    }
    
    func clearQueue() async {
        await OfflineQueue.shared.clearQueue()
        await updateQueueCount()
    }
}
```

## Example: SwiftUI View

```swift
struct MyView: View {
    @StateObject private var viewModel = MyViewModel()
    
    var body: some View {
        VStack {
            Text("Queued: \(viewModel.queueCount)")
            
            Button("Clear Queue") {
                Task {
                    await viewModel.clearQueue()
                }
            }
        }
        .task {
            // Runs when view appears
            await viewModel.updateQueueCount()
        }
    }
}
```

## Why This Change?

### Benefits:
1. **Thread Safety**: Actors automatically prevent data races
2. **No Manual Locks**: Simpler, cleaner code
3. **Swift Concurrency**: Better integration with async/await
4. **Compiler Enforced**: Catches threading issues at compile time

### Trade-off:
- Must use `await` everywhere (which is actually a good thing - makes async operations explicit)

## Search Your Codebase

To find all places that might need updating, search for:

```bash
# In terminal:
grep -r "OfflineQueue.shared" --include="*.swift" .

# Look for these patterns:
# - OfflineQueue.shared.getQueueCount()
# - OfflineQueue.shared.enqueue(...)
# - OfflineQueue.shared.processQueue()
# - OfflineQueue.shared.clearQueue()
```

Then ensure each call is properly awaited in an async context.

## Already Fixed

The following have been updated:
- ✅ `FinanceDashboardViewModel.updateQueuedCount()`
- ✅ `ErrorHandlingViews.OfflineBannerView`
- ✅ `OfflineQueue` extensions in `NexusAPI`

## Need Help?

If you get stuck with an error:
1. Make the calling method `async`
2. Add `await` before the call
3. If in a sync context (like `init` or button), wrap in `Task { await ... }`
