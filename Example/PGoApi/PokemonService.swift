//
//  PokemonService.swift
//  PGoApi
//
//  Created by Harsh Singh on 2016-08-11.
//  Copyright © 2016 CocoaPods. All rights reserved.
//

import Foundation
import PGoApi
import CoreLocation

class PokemonService {
    var request = PGoApiRequest()
    var auth: PGoAuth?
    
    static let sharedInstance = PokemonService()
    
    init() {
    }
    func updateLocation(lat: Double = 43.721098, long: Double = -79.545725) {
        request.setLocation(lat, longitude: long, altitude: 1.0)
    }
    
    func simulateAppStartAndMakeLoginRequest() {
        // Init with auth
        request = PGoApiRequest(auth: auth)
        updateLocation()

        print("Starting simulation...")
        // Simulate the start
        request.simulateAppStart()

    }
    
    func login(completion:(response:PGoApiResponse?, status: PGoApiStatus?) -> Void) {
        simulateAppStartAndMakeLoginRequest()
        request.makeRequest(.Login, completion: {
            responseIntent, status, response in
                completion(response: response, status: status)
        })
    }
    
    func getMapObjects(completion:(response:PGoApiResponse?, status: PGoApiStatus?) -> Void) {
        self.request.getMapObjects()
        self.request.makeRequest(.GetMapObjects, completion: {
            responseIntent, status, response in
                completion(response: response, status: status)
        })
    }
    
    func updateLocation(completion:(response:PGoApiResponse?, status: PGoApiStatus?) -> Void) {
        self.request.updatePlayer()
        self.request.makeRequest(.PlayerUpdate, completion: {
            responseIntent, status, response in
            completion(response: response, status: status)
        })
    }
    
    
}