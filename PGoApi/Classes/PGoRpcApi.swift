//
//  RPC.swift
//  pgomap
//
//  Based on https://github.com/tejado/pgoapi/blob/master/pgoapi/rpc_api.py
//
//  Created by Luke Sapan on 7/20/16.
//  Copyright © 2016 Coadstal. All rights reserved.
//

import Foundation
import Alamofire
import ProtocolBuffers


class PGoRpcApi {
    private let intent: PGoApiIntent
    private var auth: PGoAuth
    private let delegate: PGoApiDelegate?
    private let subrequests: [PGoApiMethod]
    private let api: PGoApiRequest
    private let encrypt: PGoEncrypt
    private var locationHex: Array<UInt8>
    private var manager: Manager? = nil
    private var authInfo: NSData? = nil
    
    internal init(subrequests: [PGoApiMethod], intent: PGoApiIntent, auth: PGoAuth, api: PGoApiRequest, delegate: PGoApiDelegate?) {
        manager = auth.manager
        manager!.session.configuration.HTTPAdditionalHeaders = [
            "User-Agent": "Niantic App"
        ]
        
        self.subrequests = subrequests
        self.intent = intent
        self.auth = auth
        self.delegate = delegate
        self.api = api
        self.locationHex = []
        self.encrypt = PGoEncrypt()
    }
    
    internal func request() {
        let requestData = buildMainRequest().data()
        
        manager!.request(.POST, auth.endpoint, parameters: [:], encoding: .Custom({
            (convertible, params) in
            let mutableRequest = convertible.URLRequest.copy() as! NSMutableURLRequest
            mutableRequest.HTTPBody = requestData
            return (mutableRequest, nil)
        })).responseData { response in
            let statusCode = response.response?.statusCode
            if statusCode != 200 {
                print("Unexpected response code, should be 200, got \(statusCode)")
                self.delegate?.didReceiveApiError(self.intent, statusCode: statusCode)
                return
            }
            
            print("Got a response!")
            self.delegate?.didReceiveApiResponse(self.intent, response: self.parseMainResponse(response.result.value!))
        }
    }
    
    private func toByteArray<T>(value_: T) -> [UInt8] {
        var value = value_
        return withUnsafePointer(&value) {
            Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: 8))
        }
    }
    
    private func locationToHex(lat: Double, long: Double, accuracy: Double) -> Array<UInt8> {
        var LocationData: Array<UInt8> = []
        LocationData.appendContentsOf(toByteArray(lat).reverse())
        LocationData.appendContentsOf(toByteArray(long).reverse())
        LocationData.appendContentsOf(toByteArray(accuracy).reverse())
        return LocationData
    }
    
    private func getAuthData() -> Array<UInt8> {
        var authData: Array<UInt8> = []
        
        if auth.authToken != nil {
            authData = auth.authToken!.data().getUInt8Array()
        } else {
            authData = self.authInfo!.getUInt8Array()
        }
        
        return authData
    }
    
    private func generateAuthInfo() -> Pogoprotos.Networking.Envelopes.RequestEnvelope.AuthInfo {
        let authInfoBuilder = Pogoprotos.Networking.Envelopes.RequestEnvelope.Builder().getAuthInfoBuilder()
        let authInfoTokenBuilder = authInfoBuilder.getTokenBuilder()
        authInfoBuilder.provider = auth.authType.description
        authInfoTokenBuilder.contents = auth.accessToken!
        authInfoTokenBuilder.unknown2 = 59
        let authData = try! authInfoBuilder.build()
        self.authInfo = authData.data()
        return authData
    }
    
    private func hashAuthTicket() -> UInt32 {
        let xxh32:xxhash = xxhash()
        let firstHash = xxh32.xxh32(0x61656632, input: getAuthData())
        return xxh32.xxh32(firstHash, input: self.locationHex)
    }
    
    private func hashLocation() -> UInt32 {
        let xxh32:xxhash = xxhash()
        self.locationHex = locationToHex(self.api.Location.lat, long:self.api.Location.long, accuracy: self.api.Location.horizontalAccuracy)
        return xxh32.xxh32(0x61656632, input: locationHex)
    }
    
    private func hashRequest(requestData:NSData) -> UInt64 {
        let xxh64:xxhash = xxhash()
        let firstHash = xxh64.xxh64(0x61656632, input: getAuthData())
        return xxh64.xxh64(firstHash, input: requestData.getUInt8Array())
    }
    
    private func generateLocationFixArray() -> UInt64 {
        let msSinceLastLocationFix = UInt64.random(200, max: 300)
        self.api.Settings.LocationFixes = [generateLocationFix(UInt64.random(500, max: 750)),
                                           generateLocationFix(UInt64.random(350, max: 450)),
                                           generateLocationFix(msSinceLastLocationFix)]
        return msSinceLastLocationFix
    }
    
    private func generateLocationFixTimeStamp() -> UInt64 {
        var msSinceLastLocationFix:UInt64 = 0
        if self.api.Settings.LocationFixes.count == 0 {
            msSinceLastLocationFix = generateLocationFixArray()
        } else {
            if self.api.Settings.LocationFixes[0].timestampSnapshot + 1000 < self.api.getTimestamp() {
                self.api.Settings.LocationFixes[1].timestampSnapshot += self.api.getTimestampSinceStart()
                self.api.Settings.LocationFixes[2].timestampSnapshot += self.api.getTimestampSinceStart()
                msSinceLastLocationFix = UInt64.random(200, max: 300)
                self.api.Settings.LocationFixes.removeFirst()
                self.api.Settings.LocationFixes.append(generateLocationFix(msSinceLastLocationFix))
            } else {
                self.api.Settings.LocationFixes[0].timestampSnapshot += self.api.getTimestampSinceStart()
                self.api.Settings.LocationFixes[1].timestampSnapshot += self.api.getTimestampSinceStart()
                self.api.Settings.LocationFixes[2].timestampSnapshot += self.api.getTimestampSinceStart()
                msSinceLastLocationFix = self.api.Settings.LocationFixes.last!.timestampSnapshot
            }
        }
        return msSinceLastLocationFix
    }
    
    private func generateLocationFix(timeStamp: UInt64) -> Pogoprotos.Networking.Envelopes.Signature.LocationFix.Builder {
        let locFix = Pogoprotos.Networking.Envelopes.Signature.LocationFix.Builder()
        locFix.provider = "fused"
        locFix.timestampSnapshot = timeStamp
        locFix.latitude = Float(self.api.Location.lat) + Float.random(min: -0.01, max: 0.01)
        locFix.longitude = Float(self.api.Location.long) + Float.random(min: -0.01, max: 0.01)
        locFix.altitude = Float(self.api.Location.alt) + Float.random(min: -0.01, max: 0.01)
        if self.api.Location.speed != nil {
            locFix.speed = Float(self.api.Location.speed!) + Float.random(min: -0.01, max: 0.01)
        } else {
            locFix.speed = Float.random(min: 1.0, max: 5.0)
        }
        if self.api.Location.speed != nil {
            locFix.course = Float(self.api.Location.course!) + Float.random(min: -0.01, max: 0.01)
        } else {
            locFix.course = Float.random(min: 0, max: 360)
        }
        if self.api.Location.floor != nil {
            locFix.floor = self.api.Location.floor!
        }
        locFix.course = Float(self.api.Location.horizontalAccuracy) + Float.random(min: -0.01, max: 0.01)
        locFix.providerStatus = 3
        locFix.locationType = 1
        return locFix
    }
    
    // Data from https://github.com/PokemonGoF/PokemonGo-Bot/blob/master/pokemongo_bot/api_wrapper.py
    
    private func getSensorInfo() -> Pogoprotos.Networking.Envelopes.Signature.SensorInfo {
        let sensorInfoBuilder = Pogoprotos.Networking.Envelopes.Signature.SensorInfo.Builder()
        sensorInfoBuilder.timestampSnapshot = self.api.getTimestampSinceStart() + self.api.Settings.realisticStartTimeAdjustment
        sensorInfoBuilder.linearAccelerationX = Double(Float.random(min: -0.139084026217, max: 0.138112977147))
        sensorInfoBuilder.linearAccelerationY = Double(Float.random(min: -0.2, max: 0.19))
        sensorInfoBuilder.linearAccelerationZ = Double(Float.random(min: -0.2, max: 0.4))
        sensorInfoBuilder.magneticFieldX = Double(Float.random(min: -47.149471283, max: 61.8397789001))
        sensorInfoBuilder.magneticFieldY = Double(Float.random(min: -47.149471283, max: 61.8397789001))
        sensorInfoBuilder.magneticFieldZ = Double(Float.random(min: -47.149471283, max: 5))
        sensorInfoBuilder.rotationVectorX = Double(Float.random(min: 0.0729667818829, max: 0.0729667818829))
        sensorInfoBuilder.rotationVectorY = Double(Float.random(min: -2.788630499244109, max:  3.0586791383810468))
        sensorInfoBuilder.rotationVectorZ = Double(Float.random(min: -0.34825887123552773, max: 0.19347580173737935))
        sensorInfoBuilder.gyroscopeRawX = Double(Float.random(min: -0.9703824520111084, max: 0.8556089401245117))
        sensorInfoBuilder.gyroscopeRawY = Double(Float.random(min: -1.7470258474349976, max:  1.4218578338623047))
        sensorInfoBuilder.gyroscopeRawZ = Double(Float.random(min: -0.9681901931762695, max: 0.8396636843681335))
        sensorInfoBuilder.gravityX = Double(Float.random(min: -0.31110161542892456, max: 0.1681540310382843))
        sensorInfoBuilder.gravityY = Double(Float.random(min: -0.6574847102165222, max:  -0.07290205359458923))
        sensorInfoBuilder.gravityZ = Double(Float.random(min: -0.9943905472755432, max: -0.7463029026985168))

        return try! sensorInfoBuilder.build()
    }
    
    private func getActivityStatus() -> Pogoprotos.Networking.Envelopes.Signature.ActivityStatus {
        let activityStatusBuilder = Pogoprotos.Networking.Envelopes.Signature.ActivityStatus.Builder()
        return try! activityStatusBuilder.build()
    }
    
    private func getDeviceInfo() -> Pogoprotos.Networking.Envelopes.Signature.DeviceInfo {
        let deviceInfoBuilder = Pogoprotos.Networking.Envelopes.Signature.DeviceInfo.Builder()
        deviceInfoBuilder.deviceId = self.api.device.deviceId
        if self.api.device.androidBoardName != nil {
            deviceInfoBuilder.androidBoardName = self.api.device.androidBoardName!
        }
        if self.api.device.androidBootloader != nil {
            deviceInfoBuilder.androidBootloader = self.api.device.androidBootloader!
        }
        if self.api.device.deviceBrand != nil {
            deviceInfoBuilder.deviceBrand = self.api.device.deviceBrand!
        }
        if self.api.device.deviceModel != nil {
            deviceInfoBuilder.deviceModel = self.api.device.deviceModel!
        }
        if self.api.device.deviceModelIdentifier != nil {
            deviceInfoBuilder.deviceModelIdentifier = self.api.device.deviceModelIdentifier!
        }
        if self.api.device.deviceModelBoot != nil {
            deviceInfoBuilder.deviceModelBoot = self.api.device.deviceModelBoot!
        }
        if self.api.device.hardwareManufacturer != nil {
            deviceInfoBuilder.hardwareManufacturer = self.api.device.hardwareManufacturer!
        }
        if self.api.device.hardwareModel != nil {
            deviceInfoBuilder.hardwareModel = self.api.device.hardwareModel!
        }
        if self.api.device.firmwareBrand != nil {
            deviceInfoBuilder.firmwareBrand = self.api.device.firmwareBrand!
        }
        if self.api.device.firmwareTags != nil {
            deviceInfoBuilder.firmwareTags = self.api.device.firmwareTags!
        }
        if self.api.device.firmwareType != nil {
            deviceInfoBuilder.firmwareType = self.api.device.firmwareType!
        }
        if self.api.device.firmwareFingerprint != nil {
            deviceInfoBuilder.firmwareFingerprint = self.api.device.firmwareFingerprint!
        }
        return try! deviceInfoBuilder.build()
    }
    
    private func buildPlatformRequest(requestHashes: Array<UInt64>) -> Pogoprotos.Networking.Envelopes.RequestEnvelope.PlatformRequest {
        let signatureBuilder = Pogoprotos.Networking.Envelopes.Signature.Builder()
        
        signatureBuilder.locationHash2 = hashLocation()
        signatureBuilder.locationHash1 = hashAuthTicket()
        signatureBuilder.unknown25 = self.api.Settings.versionHash
        signatureBuilder.timestamp = self.api.getTimestamp()
        signatureBuilder.timestampSinceStart = self.api.getTimestampSinceStart() + self.api.Settings.realisticStartTimeAdjustment
        signatureBuilder.requestHash = requestHashes
        
        if self.api.Settings.sessionHash == nil {
            self.api.Settings.sessionHash = NSData.randomBytes(16)
        }
        signatureBuilder.sessionHash = self.api.Settings.sessionHash!
        
        signatureBuilder.locationFix = [try! self.api.Settings.LocationFixes[0].build(),
                                        try! self.api.Settings.LocationFixes[1].build(),
                                        try! self.api.Settings.LocationFixes[2].build()]
        
        signatureBuilder.activityStatus = getActivityStatus()
        signatureBuilder.deviceInfo = getDeviceInfo()
        signatureBuilder.sensorInfo = getSensorInfo()
        
        let signature = try! signatureBuilder.build()
        
        let unknown6 = Pogoprotos.Networking.Envelopes.RequestEnvelope.PlatformRequest.Builder()
        let unknown2 = Pogoprotos.Networking.Platform.Requests.SendEncryptedSignatureRequest.Builder()
        
        unknown6.types = .SendEncryptedSignature
        
        let sigData = self.encrypt.encrypt(signature.data().getUInt8Array())
        unknown2.encryptedSignature = NSData(bytes: sigData, length: sigData.count)
        
        unknown6.requestMessage = try! unknown2.build().data()
        let unknown6Version35 = try! unknown6.build()
        
        return unknown6Version35
    }
    
    private func buildMainRequest() -> Pogoprotos.Networking.Envelopes.RequestEnvelope {
        print("Generating main request...")
        
        let requestBuilder = Pogoprotos.Networking.Envelopes.RequestEnvelope.Builder()
        requestBuilder.statusCode = 2
        requestBuilder.requestId = self.api.Settings.requestId
        requestBuilder.msSinceLastLocationfix = Int64(generateLocationFixTimeStamp())
        
        requestBuilder.latitude = self.api.Location.lat
        requestBuilder.longitude = self.api.Location.long
        requestBuilder.accuracy = self.api.Location.horizontalAccuracy
        
        print("Generating subrequests...")
        var requestHashes:Array<UInt64> = []

        for subrequest in subrequests {
            print("Processing \(subrequest)...")
            let subrequestBuilder = Pogoprotos.Networking.Requests.Request.Builder()
            subrequestBuilder.requestType = subrequest.id
            subrequestBuilder.requestMessage = subrequest.message.data()
            let subData = try! subrequestBuilder.build()
            requestBuilder.requests += [subData]
            if auth.authToken != nil {
                let h64 = hashRequest(subData.data())
                requestHashes.append(h64)
            }
        }
        
        if auth.authToken == nil {
            requestBuilder.authInfo = generateAuthInfo()
        } else {
            requestBuilder.authTicket = auth.authToken!
        }
        
        requestBuilder.platformRequests = [buildPlatformRequest(requestHashes)]
        
        self.api.Settings.requestId += 1
        
        print("Building request...")
        return try! requestBuilder.build()
    }
    
    private func parseMainResponse(data: NSData) -> PGoApiResponse {
        print("Parsing main response...")
        
        let response = try! Pogoprotos.Networking.Envelopes.ResponseEnvelope.parseFromData(data)
        
        if response.statusCode == .BadRequest {
            self.auth.banned = true
            print("WARNING: Account may be banned.")
            self.delegate?.didReceiveApiException(intent, exception: .Banned)
        } else if response.statusCode == .Redirect {
            auth.endpoint = "https://\(response.apiUrl)/rpc"
            print("New endpoint: \(auth.endpoint)")
        } else if response.statusCode == .InvalidAuthToken {
            print("Auth token is expired.")
            if (self.api.Settings.refreshAuthTokens) {
                self.api.refreshAuthToken()
            } else {
                auth.expired = true
                self.delegate?.didReceiveApiException(intent, exception: .AuthTokenExpired)
            }
        } else if response.statusCode == .InvalidRequest {
            print("Warning! Request was invalid.")
            self.delegate?.didReceiveApiException(intent, exception: .InvalidRequest)
        } else if response.statusCode == .InvalidPlatformRequest {
            print("Warning! Platform request is invalid. Try adding a delay of 10 seconds.")
            self.delegate?.didReceiveApiException(intent, exception: .DelayRequired)
        } else if response.statusCode == .SessionInvalidated {
            print("Warning! Session is invalid.")
            self.delegate?.didReceiveApiException(intent, exception: .SessionInvalidated)
        } else if response.statusCode == .Unknown {
            print("Warning! Unknown error.")
            self.delegate?.didReceiveApiException(intent, exception: .Unknown)
        }
        
        if response.hasAuthTicket {
            auth.authToken = response.authTicket
        }
        
        let subresponses = parseSubResponses(response)
        return PGoApiResponse(response: response, subresponses: subresponses)
    }
    
    private func parseSubResponses(response: Pogoprotos.Networking.Envelopes.ResponseEnvelope) -> [GeneratedMessage] {
        print("Parsing subresponses...")
        
        var subresponses: [GeneratedMessage] = []
        for (idx, subresponseData) in response.returns.enumerate() {
            let subrequest = subrequests[idx]
            subresponses.append(subrequest.parser(subresponseData))
        }
        return subresponses
    }
}
