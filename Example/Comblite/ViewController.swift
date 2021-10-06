//
//  ViewController.swift
//  Comblite
//
//  Created by ggaljjak on 08/11/2021.
//  Copyright (c) 2021 ggaljjak. All rights reserved.
//

import UIKit
import Comblite
import Combine

class User: Serializable {
    var id: Int64 = 0
    var name: String? = nil
    var profile: String? = nil
    
    required init() {}
    
    init(_ id: Int64, name: String?) {
        self.id = id
        self.name = name
    }
}

class ViewController: UIViewController {
    
    private var subscriptions = Set<AnyCancellable>()
    let db = CombliteHelper()
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func exampleForBasicUse() {
        let comblite = Comblite("path/To/Database.sqlite3", dbVersion: 1)
        
        // Create Table
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
        
        // Insert
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
        
        // Select with dictionary
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
        
        // Select with Class Type
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
        
        // Simple Int
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
        
        // Delete
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
    }
}

class CombliteHelper: CombliteDelegate {
    private var subscriptions = Set<AnyCancellable>()
    private let comblite: Comblite
    
    init() {
        let fileMgr = FileManager()
        let docPathUrl = fileMgr.urls(for: .documentDirectory, in: .userDomainMask).first!
        let path = docPathUrl.appendingPathComponent("Database.sqlite3").path
        
        comblite = Comblite(path, dbVersion: 1)
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
    
    func loadUserList() -> AnyPublisher<[User], CLError> { comblite.query("SELECT * FROM User") }
    
    func insertUser(_ name: String) -> AnyPublisher<User, CLError> {
        return comblite.insert("INSERT INTO User (name) VALUES (?)", args: [name])
            .map { index in User(index, name: name) }
            .eraseToAnyPublisher()
    }
}

