# Comblite

[![Version](https://img.shields.io/cocoapods/v/Comblite.svg?style=flat)](https://cocoapods.org/pods/Comblite)
[![License](https://img.shields.io/cocoapods/l/Comblite.svg?style=flat)](https://cocoapods.org/pods/Comblite)
[![Platform](https://img.shields.io/cocoapods/p/Comblite.svg?style=flat)](https://cocoapods.org/pods/Comblite)

Comblite is Combine + Sqlite wrapping library for Swift.

## Requirements

- Platform : iOS 13.0+
- Swift Version : 4+

## Installation

### Cocoapods

```ruby
pod 'Comblite'
```

# Example 

## Usage


```swift
let comblite = Comblite("path/To/Database.sqlite3")

// Return Nothing
public func exec(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Void, CLError> 

// Return Total Affected rows
public func run(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Int32, CLError>

// Return last_insert_rowid
public func insert(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Int64, CLError>

// Return data dictionary
public func query(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<[[String: Any]], CLError>

// Return data object
public func query<T: NSObject>(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<[T], CLError>

// Return query first value (int)
public func singleInt(_ sql: String, args: [Any?]? = nil, defaultValue: Int64? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Int64?, CLError>

// Return query first value (string)
public func singleString(_ sql: String, args: [Any?]? = nil, defaultValue: String? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<String?, CLError>

```

## Basic

### Initialize

```swift
let comblite = Comblite("path/To/Database.sqlite3")
```

### Exec

The `exec` method return nothing

```swift
comblite.exec("CREATE TABLE User (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)")
    .receive(on: DispatchQueue.main)
    .sink { completion in
        switch completion {
        case .failure(let err):
            print("Failed \(err)")
            break
        case .finished:
            print("Table created")
            break
        }
    } receiveValue: { _ in }
    .store(in: &subscriptions)
```

### Insert

`insert` method return `last_insert_rowid`

```swift
comblite.insert("INSERT INTO User (name) VALUES (?)", args: ["Jack"])
    .sink { completion in
        switch completion {
        case .failure(let err):
            print("Failed \(err)")
            break
        case .finished:
            print("User inserted")
            break
        }
    } receiveValue: { index in
        print("New user index is \(index)")
    }
    .store(in: &subscriptions)
```

### Query Array with dictionary

`[[String:Any?]]`

```swift
comblite.query("SELECT * FROM User")
    .sink { completion in
        switch completion {
        case .failure(let err):
            print("Failed \(err)")
            break
        case .finished:
            print("User inserted")
            break
        }
    } receiveValue: { users in
        for user in users {
            print("Index : \(String(describing: user["id"])), Name : \(String(describing: user["name"]))")
        }
    }
    .store(in: &subscriptions)
```

### Query Array with object

This method must implement `NSObject` and contain `@objMembers` or `@objc`.
Return type is `T: NSObject`

```swift
@objcMembers
class User: NSObject {
    var id: Int64 = 0
    var name: String? = nil
}
// or
class User: NSObject {
    @objc var id: Int64 = 0
    @objc var name: String? = nil
}

comblite.query("SELECT * FROM User")
    .sink { completion in
        switch completion {
        case .failure(let err):
            print("Failed \(err)")
            break
        case .finished:
            print("User inserted")
            break
        }
    } receiveValue: { (users: [User]) in
        for user in users {
            print("Index : \(user.id), Name : \(String(describing: user.name))")
        }
    }
    .store(in: &subscriptions)
```

### SingleInt

This function returns the *first* data of the search result as `Int` type.

```swift
comblite.singleInt("SELECT COUNT(*) FROM User")
    .sink { completion in
        switch completion {
        case .failure(let err):
            print("Failed \(err)")
            break
        case .finished:
            print("User inserted")
            break
        }
    } receiveValue: { count in
        print("User has \(String(describing: count))")
    }
    .store(in: &subscriptions)
```

### Run

The `run` method returns. the number of rows affected

```swift
comblite.run("DELETE FROM User WHERE id = ?", args: [0])
    .sink { completion in
        switch completion {
        case .failure(let err):
            print("Failed \(err)")
            break
        case .finished:
            print("User inserted")
            break
        }
    } receiveValue: { affectedRows in
        print("Affected rows : \(affectedRows)")
    }
    .store(in: &subscriptions)
```

## With helper

Comlite can also be further managed through Delegate.

```swift
class CombliteHelper: CombliteDelegate {
    private var subscriptions = Set<AnyCancellable>()
    private let comblite: Comblite
    
    init() {
        let fileMgr = FileManager()
        let docPathUrl = fileMgr.urls(for: .documentDirectory, in: .userDomainMask).first!
        let path = docPathUrl.appendingPathComponent("Database.sqlite3").path
        
        comblite = Comblite(path, dbVersion: 1) //Comblite("")
        comblite.setDelegate(self)
    }
    
    func onCreateDatabase(_ comblite: Comblite) {
        Publishers.Zip(
            comblite.exec("CREATE TABLE User (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)"),
            comblite.exec("INSERT INTO User (name) VALUES (?)", args: ["Jack"])
        )
        .receive(on: DispatchQueue.main)
        .sink { completion in
            switch completion {
            case .failure(let err):
                print("Failed \(err)")
                break
            case .finished:
                print("Table created")
                break
            }
        } receiveValue: { _ in }
        .store(in: &subscriptions)
    }
    
    func onUpgrade(_ comblite: Comblite, oldVersion: Int64, newVersion: Int64) {
        if oldVersion < 2 {
            comblite.exec("ALTER TABLE User ADD COLUMN profile TEXT")
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .failure(let err):
                        print("Failed \(err)")
                        break
                    case .finished:
                        print("Table altered")
                        break
                    }
                } receiveValue: { _ in }
                .store(in: &subscriptions)
        }
    }
    
    func onError(_ comblite: Comblite, error: CLError) {
        print("Handle Error Here : \(error)")
    }
    
    func loadUserList() -> Future<[User], CLError> { comblite.query("SELECT * FROM User") }
    
    func insertUser(_ name: String) -> AnyPublisher<User, CLError> {
        return comblite.insert("INSERT INTO User (name) VALUES (?)", args: [name])
            .map { index in User(index, name: name) }
            .eraseToAnyPublisher()
    }
}
```

# License

Comblite is available under the MIT license. See the LICENSE file for more info.
