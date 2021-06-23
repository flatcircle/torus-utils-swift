/**
 torus utils class
 Author: Shubham Rathi
 */

import Foundation
import FlatCircleFetchNodeDetails
import FlatCircleweb3swift
import PromiseKit
#if canImport(secp256k1)
import secp256k1
#endif
import CryptoSwift
import BigInt
import BestLogger

public class TorusUtils{
    static let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN|SECP256K1_CONTEXT_VERIFY))
    let nodePubKeys: Array<TorusNodePub>
    let logger: BestLogger
    
    public init(label: String = "Torus utils", loglevel: BestLogger.Level = .info, nodePubKeys: Array<TorusNodePub> = [TorusNodePub(_X: "4086d123bd8b370db29e84604cd54fa9f1aeb544dba1cc9ff7c856f41b5bf269", _Y: "fde2ac475d8d2796aab2dea7426bc57571c26acad4f141463c036c9df3a8b8e8"),TorusNodePub(_X: "1d6ae1e674fdc1849e8d6dacf193daa97c5d484251aa9f82ff740f8277ee8b7d", _Y: "43095ae6101b2e04fa187e3a3eb7fbe1de706062157f9561b1ff07fe924a9528"),TorusNodePub(_X: "fd2af691fe4289ffbcb30885737a34d8f3f1113cbf71d48968da84cab7d0c262", _Y: "c37097edc6d6323142e0f310f0c2fb33766dbe10d07693d73d5d490c1891b8dc"),TorusNodePub(_X: "e078195f5fd6f58977531135317a0f8d3af6d3b893be9762f433686f782bec58", _Y: "843f87df076c26bf5d4d66120770a0aecf0f5667d38aa1ec518383d50fa0fb88"),TorusNodePub(_X: "a127de58df2e7a612fd256c42b57bb311ce41fd5d0ab58e6426fbf82c72e742f", _Y: "388842e57a4df814daef7dceb2065543dd5727f0ee7b40d527f36f905013fa96")]){
        self.logger = BestLogger(label: label, level: loglevel)
        self.nodePubKeys = nodePubKeys
    }
    
    public func getPublicAddress(endpoints : Array<String>, torusNodePubs : Array<TorusNodePub>, verifier : String, verifierId : String, isExtended: Bool) -> Promise<[String:String]>{
        
        let (tempPromise, seal) = Promise<[String:String]>.pending()
        let keyLookup = self.keyLookup(endpoints: endpoints, verifier: verifier, verifierId: verifierId)
        
        keyLookup.then{ lookupData -> Promise<[String: String]> in
            let error = lookupData["err"]
            
            if(error != nil){
                // Assign key to the user and return (wraped in a promise)
                return self.keyAssign(endpoints: endpoints, torusNodePubs: torusNodePubs, verifier: verifier, verifierId: verifierId).then{ data -> Promise<[String:String]> in
                    // Do keylookup again
                    return self.keyLookup(endpoints: endpoints, verifier: verifier, verifierId: verifierId)
                }.then{ data -> Promise<[String: String]> in
                    
                    return Promise<[String: String]>.value(data)
                }
            }else{
                return Promise<[String: String]>.value(lookupData)
            }
        }.then{ data in
            return self.getMetadata(dictionary: ["pub_key_X": data["pub_key_X"]!, "pub_key_Y": data["pub_key_Y"]!]).map{ ($0, data) } // Tuple
        }.done{ nonce, data in
            var newData = data
            // Convert to BigInt for modulus
            let nonce2 = BigInt(nonce).modulus(BigInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!)
            if(nonce != BigInt(0)) {
                let actualPublicKey = "04" + newData["pub_key_X"]!.addLeading0sForLength64() + newData["pub_key_Y"]!.addLeading0sForLength64()
                let noncePublicKey = SECP256K1.privateToPublic(privateKey: BigUInt(nonce2).serialize().addLeading0sForLength64())
                let addedPublicKeys = self.combinePublicKeys(keys: [actualPublicKey, noncePublicKey!.toHexString()], compressed: false)
                newData["address"] = self.publicKeyToAddress(key: addedPublicKeys)
            }
            
            if(!isExtended){
                seal.fulfill(["address": newData["address"]!])
            }else{
                seal.fulfill(newData)
            }
            
        }.catch{err in
            self.logger.error("getPublicAddress: err: ", err)
            if let tmpError = err as? TorusError{
                if(tmpError == TorusError.nodesUnavailable){
                    seal.reject(TorusError.nodesUnavailable)
                }
            }
        }
        
        return tempPromise
        
    }
    
    public func retrieveShares(endpoints : Array<String>, verifierIdentifier: String, verifierId:String, idToken: String, extraParams: Data) -> Promise<[String:String]>{
        
        // Generate privatekey
        let privateKey = SECP256K1.generatePrivateKey()
        let publicKey = SECP256K1.privateToPublic(privateKey: privateKey!, compressed: false)?.suffix(64) // take last 64
        
        // Split key in 2 parts, X and Y
        let publicKeyHex = publicKey?.toHexString()
        let pubKeyX = publicKey?.prefix(publicKey!.count/2).toHexString().addLeading0sForLength64()
        let pubKeyY = publicKey?.suffix(publicKey!.count/2).toHexString().addLeading0sForLength64()
        
        // Hash the token from OAuth login
        // let tempIDToken = verifierParams.map{$0["idtoken"]!}.joined(separator: "\u{001d}")
        
        let hashedOnce = idToken.sha3(.keccak256)
        // let tokenCommitment = hashedOnce.sha3(.keccak256)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        var publicAddress: String = ""
        var lookupPubkeyX: String = ""
        var lookupPubkeyY: String = ""
        
        self.logger.debug("RetrieveShares: ", privateKey?.toHexString() as Any, publicKeyHex as Any, pubKeyX as Any, pubKeyY as Any, hashedOnce)
        
        let (tempPromise, seal) = Promise<[String:String]>.pending()
        
        // Reject if not resolved in 30 seconds
        after(.seconds(300)).done {
            seal.reject(TorusError.timeout)
        }
        
        
        
        getPublicAddress(endpoints: endpoints, torusNodePubs: nodePubKeys, verifier: verifierIdentifier, verifierId: verifierId, isExtended: true).then{ data -> Promise<[[String:String]]> in
            publicAddress = data["address"] ?? ""
            lookupPubkeyX = data["pub_key_X"]!.addLeading0sForLength64()
            lookupPubkeyY = data["pub_key_Y"]!.addLeading0sForLength64()
            return self.commitmentRequest(endpoints: endpoints, verifier: verifierIdentifier, pubKeyX: pubKeyX!, pubKeyY: pubKeyY!, timestamp: timestamp, tokenCommitment: hashedOnce)
        }.then{ data -> Promise<(String, String, String)> in
            self.logger.info("retrieveShares: data after commitment request", data)
            return self.retrieveDecryptAndReconstruct(endpoints: endpoints, extraParams: extraParams, verifier: verifierIdentifier, tokenCommitment: idToken, nodeSignatures: data, verifierId: verifierId, lookupPubkeyX: lookupPubkeyX, lookupPubkeyY: lookupPubkeyY, privateKey: (privateKey?.toHexString())!)
        }.then{ x, y, key in
            return self.getMetadata(dictionary: ["pub_key_X": x, "pub_key_Y": y]).map{ ($0, key) } // Tuple
        }.done{ nonce, key in
            if(nonce != BigInt(0)) {
                let tempNewKey = BigInt(nonce) + BigInt(key, radix: 16)!
                let newKey = tempNewKey.modulus(BigInt("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", radix: 16)!)
                self.logger.info(newKey)
                seal.fulfill(["privateKey": BigUInt(newKey).serialize().suffix(64).toHexString(), "publicAddress": publicAddress])
            }
            seal.fulfill(["privateKey":key, "publicAddress": publicAddress])
            
        }.catch{ err in
            self.logger.error("retrieveShares: err: ",err)
            seal.reject(err)
        }.finally {
            if(tempPromise.isPending){
                seal.reject(TorusError.unableToDerive)
            }
        }
        
        return tempPromise
    }
    
}
