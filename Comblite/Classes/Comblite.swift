
import SQLite3
import Combine
import SwiftUI
import Foundation

public enum CLError: Error {
    case openFailed(msg: String, code: Int32? = nil)
    case bindFailed(msg: String, code: Int32? = nil)
    case queryFailed(msg: String, code: Int32? = nil)
    case unexcepted(msg: String, code: Int32? = nil)
    case error(err: Error)
}

public class Comblite {
    private var dbFilePath: String
    private var delegate: CombliteDelegate? = nil
    private var userDbVersion: Int64
    private var dispatchQueue = DispatchQueue.global(qos: .background)
    
    public init(_ fileName: String, dbVersion: Int64 = 0) {
        self.dbFilePath = fileName
        self.userDbVersion = dbVersion
        print("Init Comblite")
    }
    
    deinit {
        print("Deinit Comblite")
    }
    
    public func setDelegate(_ delegate: CombliteDelegate) {
        self.delegate = delegate
        initializeWithDelegate()
    }
    
    private func initializeWithDelegate() {
        // Initialize Database
        guard let delegate = self.delegate else { return }
        
        let fileMgr = FileManager.default
        var isDir: ObjCBool = false
        if fileMgr.fileExists(atPath: self.dbFilePath, isDirectory: &isDir) {
            if isDir.boolValue {
                delegate.onError(self, error: CLError.openFailed(msg: "\(self.dbFilePath) is Directory"))
            }
        } else {
            delegate.onCreateDatabase(self)
            self._dbVersion = self.userDbVersion
        }
        
        // Version check
        let hasDbVersion = self._dbVersion
        print("Old db version : \(hasDbVersion) -> New db version : \(userDbVersion)")
        if hasDbVersion < self.userDbVersion {
            delegate.onUpgrade(self, oldVersion: hasDbVersion, newVersion: userDbVersion)
            self._dbVersion = userDbVersion
        }
        self.delegate?.onOpenDatabase(self)
    }
    
    private var _dbVersion: Int64 {
        get {
            var db: OpaquePointer? = nil
            guard sqlite3_open(self.dbFilePath, &db) == SQLITE_OK else { return 0 }
            defer { sqlite3_close(db) }
            
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return sqlite3_column_int64(stmt, 0)
            }
            return 0
        }
        set {
            var db: OpaquePointer? = nil
            guard sqlite3_open(self.dbFilePath, &db) == SQLITE_OK else { return }
            defer { sqlite3_close(db) }
            
            var stmt: OpaquePointer? = nil
            guard sqlite3_prepare(db, "PRAGMA user_version = \(newValue)", -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_step(stmt)
        }
    }
    
    public var dbVersion: Int64 {
        get { return self._dbVersion }
    }
    
    private func bindArguments(op: OpaquePointer?, db: OpaquePointer?, binds: [Any?]) -> CLError? {
        
        let errReturn: (OpaquePointer?) -> CLError = { op in
            let err = String(cString: sqlite3_errmsg(op))
            let code: Int32 = sqlite3_errcode(db)
            return CLError.bindFailed(msg: err, code: code)
        }
        for i in 0..<binds.count {
            let pos = Int32(i) + 1
            let bindValue = binds[i]
            if let bind = bindValue {
                if type(of: bind) is Int.Type {
                    guard sqlite3_bind_int64(op, pos, Int64(bind as! Int)) == SQLITE_OK else { return errReturn(op) }
//                    guard sqlite3_bind_int(op, pos, Int64(bind as! Int)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Int8.Type {
                    guard sqlite3_bind_int(op, pos, Int32(bind as! Int8)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Int16.Type {
                    guard sqlite3_bind_int(op, pos, Int32(bind as! Int16)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Int32.Type {
                    guard sqlite3_bind_int(op, pos, bind as! Int32) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Int64.Type {
                    guard sqlite3_bind_int64(op, pos, bind as! Int64) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Float.Type {
                    guard sqlite3_bind_double(op, pos, Double(bind as! Float)) == SQLITE_OK else { return errReturn(op) }
                } else if #available(iOS 14.0, *), type(of: bind) is Float16.Type {
                    guard sqlite3_bind_double(op, pos, Double(bind as! Float16)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Float32.Type {
                    guard sqlite3_bind_double(op, pos, Double(bind as! Float32)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Float64.Type {
                    guard sqlite3_bind_double(op, pos, Double(bind as! Float64)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is CGFloat.Type {
                    guard sqlite3_bind_double(op, pos, Double(bind as! CGFloat)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Double.Type {
                    guard sqlite3_bind_double(op, pos, bind as! Double) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is String.Type {
                    guard sqlite3_bind_text(op, pos, NSString(string: (bind as! String)).utf8String, -1, nil) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is Date.Type { // Need Int or Double tpye check
                    guard sqlite3_bind_int64(op, pos, Int64((bind as! Date).timeIntervalSince1970)) == SQLITE_OK else { return errReturn(op) }
                } else if type(of: bind) is NSData.Type {
                    let data = bind as! NSData
                    guard sqlite3_bind_blob(op, pos, data.bytes, Int32(data.length), nil) == SQLITE_OK else { return errReturn(op) }
                }
            } else {
                guard sqlite3_bind_null(op, pos) == SQLITE_OK else { return errReturn(op) }
            }
        }
        return nil
    }
    
    private func getAnyValue(_ op: OpaquePointer?, index: Int32, type typeOf: Any.Type? = nil) -> Any? {
        switch sqlite3_column_type(op, index) {
        case SQLITE_NULL:
            return nil
        case SQLITE_TEXT:
            let value = String(cString: sqlite3_column_text(op, index))
            guard let type = typeOf else { return value }
            if type == Int.self {
                return Int(value)
            } else if type == Int8.self {
                return Int8(value)
            } else if type == Int16.self {
                return Int16(value)
            } else if type == Int32.self {
                return Int32(value)
            } else if type == Int64.self {
                return Int64(value)
            } else if type == Float.self {
                return Float(value)
            // } else if type == Float16.self { // ios14.0 or newer
            //     return Float16(value)
            } else if type == Float32.self {
                return Float32(value)
            } else if type == Float64.self {
                return Float64(value)
            //} else if type == Float80.self {
            //    return Float80(value)
            } else if type == Double.self {
                return Double(value)
            } else if type == Bool.self {
                return Bool(value)
            } else if type == Date.self {
                return Date(timeIntervalSince1970: TimeInterval(value)!)
            } else if type == String.self {
                return value
            } else {
                return value
            }
        case SQLITE_INTEGER:
            let value = sqlite3_column_int64(op, index)
            guard let type = typeOf else { return value }
            if type == Int.self {
                return Int(value)
            } else if type == Int8.self {
                return Int8(value)
            } else if type == Int16.self {
                return Int16(value)
            } else if type == Int32.self {
                return Int32(value)
            } else if type == Int64.self {
                return Int64(value)
            } else if type == Float.self {
                return Float(value)
            } else if type == Float32.self {
                return Float32(value)
            } else if type == Float64.self {
                return Float64(value)
            } else if type == Double.self {
                return Double(value)
            } else if type == Bool.self {
                return value == 1
            } else if type == Date.self {
                return Date(timeIntervalSince1970: TimeInterval(Int64(value)))
            } else if type == String.self {
                return value
            } else {
                return value
            }
        case SQLITE_FLOAT:
            let value = sqlite3_column_double(op, index)
            guard let type = typeOf else { return value }
            if type == Int.self {
                return Int(value)
            } else if type == Int8.self {
                return Int8(value)
            } else if type == Int16.self {
                return Int16(value)
            } else if type == Int32.self {
                return Int32(value)
            } else if type == Int64.self {
                return Int64(value)
            } else if type == Float.self {
                return Float(value)
            } else if type == Float32.self {
                return Float32(value)
            } else if type == Float64.self {
                return Float64(value)
            } else if type == Double.self {
                return value
            } else if type == Bool.self {
                return value == 1
            } else if type == Date.self {
                return Date(timeIntervalSince1970: TimeInterval(value))
            } else if type == String.self {
                return value
            } else {
                return value
            }
        case SQLITE_BLOB:
            let len = sqlite3_column_bytes(op, index)
            let point = sqlite3_column_blob(op, index)
            if point != nil {
                return NSData(bytes: point, length: Int(len))
            }
        default:
            break
        }
        return nil
    }
    
    private func _runner(_ sql: String, runner: (OpaquePointer?, OpaquePointer?) -> Void) -> CLError? {
        var db: OpaquePointer? = nil
        
        let errReturn: (OpaquePointer?) -> CLError = { op in
            let err = String(cString: sqlite3_errmsg(op))
            let code: Int32? = sqlite3_errcode(db)
            return CLError.openFailed(msg: err, code: code)
        }
        
        guard sqlite3_open(self.dbFilePath, &db) == SQLITE_OK else { return errReturn(db) }
        defer { sqlite3_close(db) } // Think!! Perhaps this line and its parent lines should go to init and deinit.
        
        //        sqlite3_commit_hook(db, { data in
        //            print("Hook!")
        //            print(data)
        //            return 0
        //        }, nil)
        
        //        sqlite3_update_hook(db, { data, action, dbName, tableName, rowId in
        //            print("Update!")
        //            print(data)
        //            print(action) // SQLITE_DELETE, SQLITE_INSERT, SQLITE_UPDATE
        //            print(String(cString: dbName!))
        //            print(String(cString: tableName!))
        //            print(rowId)
        //        }, nil)
        
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare(db, sql, -1, &stmt, nil) == SQLITE_OK else { return errReturn(db) }
        sqlite3_reset(stmt)
        defer { sqlite3_finalize(stmt) }
        
        runner(db, stmt)
        
        return nil
    }
    
    private func _singleStep(_ sql: String, args: [Any?]? = nil, runner: (OpaquePointer?, OpaquePointer?, CLError?) -> Void) {
        let openError = self._runner(sql) { [weak self] db, stmt in
            if let args = args, let error = self?.bindArguments(op: stmt, db: db, binds: args) {
                runner(db, nil, error)
            }
            
            if sqlite3_step(stmt) == SQLITE_DONE {
                runner(db, stmt, nil)
            } else {
                let err = String(cString: sqlite3_errmsg(stmt))
                let code: Int32? = sqlite3_errcode(db)
                runner(db, nil, CLError.queryFailed(msg: err, code: code))
            }
        }
        if let err = openError {
            runner(nil, nil, err)
        }
    }
    
    public func execSync(_ sql: String, args: [Any?]? = nil) throws {
        var db: OpaquePointer? = nil
        
        let errReturn: (OpaquePointer?) -> CLError = { op in
            let err = String(cString: sqlite3_errmsg(op))
            let code: Int32? = sqlite3_errcode(db)
            return CLError.openFailed(msg: err, code: code)
        }
        
        guard sqlite3_open(self.dbFilePath, &db) == SQLITE_OK else { throw errReturn(db) }
        defer { sqlite3_close(db) } // Think!! Perhaps this line and its parent lines should go to init and deinit.
        
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw errReturn(db) }
        sqlite3_reset(stmt)
        defer { sqlite3_finalize(stmt) }
        
        if let args = args, let error = self.bindArguments(op: stmt, db: db, binds: args) {
            throw error
        }
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            // Do nothing
            //runner(db, stmt, nil)
        } else {
            let err = String(cString: sqlite3_errmsg(stmt))
            let code: Int32? = sqlite3_errcode(db)
            throw CLError.queryFailed(msg: err, code: code)
        }
    }
    
    public func exec(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<Void, CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync {
                    self?._singleStep(sql, args: args) { _, _, error in
                        if let err = error {
                            return promise(.failure(err))
                        } else {
                            return promise(.success(()))
                        }
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func run(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<Int32, CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync {
                    self?._singleStep(sql, args: args) { db, statement, error in
                        if let err = error {
                            return promise(.failure(err))
                        } else {
                            promise(.success(sqlite3_total_changes(db)))
                        }
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func insert(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<Int64, CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync {
                    self?._singleStep(sql, args: args) { db, statement, error in
                        if let err = error {
                            return promise(.failure(err))
                        } else {
                            return promise(.success(sqlite3_last_insert_rowid(db)))
                        }
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func query(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<[[String: Any]], CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync {
                    let openError = self?._runner(sql) { [weak self] db, stmt in
                        if let args = args, let error = self?.bindArguments(op: stmt, db: db, binds: args) {
                            return promise(.failure(error))
                        }
                        
                        var result = [[String: Any]]()
                        
                        while (sqlite3_step(stmt) == SQLITE_ROW) {
                            var element = [String: Any]()
                            for i in 0..<sqlite3_column_count(stmt) {
                                element[String(cString: sqlite3_column_name(stmt, i))] = self?.getAnyValue(stmt, index: i)
                            }
                            result.append(element)
                        }
                        promise(.success(result))
                    }
                    if let err = openError {
                        promise(.failure(err))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func query<T: Serializable>(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<[T], CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync(execute: { [weak self] in
                    let openError = self?._runner(sql) { [weak self] db, stmt in
                        if let args = args, let error = self?.bindArguments(op: stmt, db: db, binds: args) {
                            return promise(.failure(error))
                        }
                        
                        let object = T()
                        let reflect = Mirror(reflecting: object.self)
                        
                        var result = [T]()
                        var parseError: CLError? = nil
                        
                        while (sqlite3_step(stmt) == SQLITE_ROW && parseError == nil) {
                            var element = [String: Any]()
                            for i in 0..<sqlite3_column_count(stmt) {
                                let key = String(cString: sqlite3_column_name(stmt, i))
                                element[key] = self?.getAnyValue(stmt, index: i)
                            }
                            for child in reflect.children {
                                if !element.contains(where: { $0.key == child.label }) {
                                    guard let key = child.label else { continue }
                                    element[key] = child.value
                                }
                            }
                            guard let json = try? JSONSerialization.data(withJSONObject: element, options: .prettyPrinted) else { continue }
                            do {
                                let data = try JSONDecoder().decode(T.self, from: json)
                                result.append(data)
                            } catch {
                                parseError = CLError.error(err: error)
                            }
                        }
                        if let err = parseError {
                            promise(.failure(err))
                        } else {
                            promise(.success(result))
                        }
                    }
                    if let err = openError {
                        promise(.failure(err))
                    }
                })
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func queryFirst<T: Serializable>(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<T?, CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync {
                    let openError = self?._runner(sql) { [weak self] db, stmt in
                        if let args = args, let error = self?.bindArguments(op: stmt, db: db, binds: args) {
                            return promise(.failure(error))
                        }
                        if sqlite3_step(stmt) == SQLITE_ROW {
                            let object = T()
                            let reflect = Mirror(reflecting: object.self)
                            
                            var element = [String: Any]()
                            for i in 0..<sqlite3_column_count(stmt) {
                                let key = String(cString: sqlite3_column_name(stmt, i))
                                element[key] = self?.getAnyValue(stmt, index: i)
                            }
                            for child in reflect.children {
                                if !element.contains(where: { $0.key == child.label }) {
                                    guard let key = child.label else { continue }
                                    element[key] = child.value
                                }
                            }
                            do {
                                let json = try JSONSerialization.data(withJSONObject: element, options: .prettyPrinted)
                                let data = try JSONDecoder().decode(T.self, from: json)
                                promise(.success(data))
                            } catch {
                                promise(.failure(CLError.error(err: error)))
                            }
                            
                        } else {
                            promise(.success(nil))
                        }
                    }
                    if let err = openError {
                        promise(.failure(err))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func queryFirstSync<T: Serializable>(_ sql: String, args: [Any?]? = nil) throws -> T? {
        var db: OpaquePointer? = nil
        
        let errReturn: (OpaquePointer?) -> CLError = { op in
            let err = String(cString: sqlite3_errmsg(op))
            let code: Int32? = sqlite3_errcode(db)
            return CLError.openFailed(msg: err, code: code)
        }
        
        guard sqlite3_open(self.dbFilePath, &db) == SQLITE_OK else { throw errReturn(db) }
        defer { sqlite3_close(db) } // Think!! Perhaps this line and its parent lines should go to init and deinit.
        
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw errReturn(db) }
        sqlite3_reset(stmt)
        defer { sqlite3_finalize(stmt) }
        
        if let args = args, let error = self.bindArguments(op: stmt, db: db, binds: args) {
            throw error
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            let object = T()
            let reflect = Mirror(reflecting: object.self)
            
            var element = [String: Any]()
            for i in 0..<sqlite3_column_count(stmt) {
                let key = String(cString: sqlite3_column_name(stmt, i))
                element[key] = self.getAnyValue(stmt, index: i)
            }
            for child in reflect.children {
                if !element.contains(where: { $0.key == child.label }) {
                    guard let key = child.label else { continue }
                    element[key] = child.value
                }
            }
            do {
                let json = try JSONSerialization.data(withJSONObject: element, options: .prettyPrinted)
                let data = try JSONDecoder().decode(T.self, from: json)
                return data
            } catch {
                throw CLError.error(err: error)
            }
        } else {
            let err = String(cString: sqlite3_errmsg(stmt))
            let code: Int32? = sqlite3_errcode(db)
            throw CLError.queryFailed(msg: err, code: code)
        }
    }
    
    public func singleInt(_ sql: String, args: [Any?]? = nil, defaultValue: Int64? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<Int64?, CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync {
                    let openError = self?._runner(sql) { [weak self] db, stmt in
                        if let args = args, let error = self?.bindArguments(op: stmt, db: db, binds: args) {
                            return promise(.failure(error))
                        }
                        if sqlite3_step(stmt) == SQLITE_ROW {
                            promise(.success(sqlite3_column_int64(stmt, 0)))
                        } else {
                            promise(.success(defaultValue))
                        }
                    }
                    if let err = openError {
                        promise(.failure(err))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    public func singleIntSync(_ sql: String, args: [Any?]? = nil) throws -> Int64 {
        var db: OpaquePointer? = nil
        
        let errReturn: (OpaquePointer?) -> CLError = { op in
            let err = String(cString: sqlite3_errmsg(op))
            let code: Int32? = sqlite3_errcode(db)
            return CLError.openFailed(msg: err, code: code)
        }
        
        guard sqlite3_open(self.dbFilePath, &db) == SQLITE_OK else { throw errReturn(db) }
        defer { sqlite3_close(db) } // Think!! Perhaps this line and its parent lines should go to init and deinit.
        
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw errReturn(db) }
        sqlite3_reset(stmt)
        defer { sqlite3_finalize(stmt) }
        
        if let args = args, let error = self.bindArguments(op: stmt, db: db, binds: args) {
            throw error
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            // Do nothing
            //runner(db, stmt, nil)
            return sqlite3_column_int64(stmt, 0)
        } else {
            let err = String(cString: sqlite3_errmsg(stmt))
            let code: Int32? = sqlite3_errcode(db)
            throw CLError.queryFailed(msg: err, code: code)
        }
    }
    
    public func singleString(_ sql: String, args: [Any?]? = nil, defaultValue: String? = nil, runThread: DispatchQueue? = nil) -> AnyPublisher<String?, CLError> {
        return Deferred {
            Future { [weak self] promise in
                (runThread ?? self?.dispatchQueue)?.sync {
                    let openError = self?._runner(sql) { [weak self] db, stmt in
                        if let args = args, let error = self?.bindArguments(op: stmt, db: db, binds: args) {
                            return promise(.failure(error))
                        }
                        if sqlite3_step(stmt) == SQLITE_ROW {
                            promise(.success(String(cString: sqlite3_column_text(stmt, 0))))
                        } else {
                            promise(.success(defaultValue))
                        }
                    }
                    if let err = openError {
                        promise(.failure(err))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

public protocol CombliteDelegate {
    func onCreateDatabase(_ comblite: Comblite)
    func onUpgrade(_ comblite: Comblite, oldVersion: Int64, newVersion: Int64)
    func onError(_ comblite: Comblite, error: CLError)
    func onOpenDatabase(_ comblite: Comblite)
}

public protocol Serializable: Codable {
    init()
}

//class Comblite_Example {
//    // Return Nothing
//    public func exec(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Void, CLError>
//
//    // Return Total Affected rows
//    public func run(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Int32, CLError>
//
//    // Return last_insert_rowid
//    public func insert(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Int64, CLError>
//
//    // Return data dictionary
//    public func query(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<[[String: Any]], CLError>
//
//    // Return data object
//    public func query<T: NSObject>(_ sql: String, args: [Any?]? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<[T], CLError>
//
//    // Return query first value (int)
//    public func singleInt(_ sql: String, args: [Any?]? = nil, defaultValue: Int64? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<Int64?, CLError>
//
//    // Return query first value (string)
//    public func singleString(_ sql: String, args: [Any?]? = nil, defaultValue: String? = nil, runThread: DispatchQueue = DispatchQueue.global(qos: .background)) -> Future<String?, CLError>
//}
