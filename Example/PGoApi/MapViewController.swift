//
//  ViewController.swift
//  PGoApi
//
//  Created by Luke Sapan on 08/02/2016.
//  Copyright (c) 2016 Luke Sapan. All rights reserved.
//

import UIKit
import PGoApi
import MapKit

class MapViewController: UIViewController, MKMapViewDelegate, UIGestureRecognizerDelegate {

    var auth: GPSOAuth!
    var request = PGoApiRequest()
    
    @IBOutlet var mapView: MKMapView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let center = CLLocationCoordinate2D(latitude: 43.721098, longitude: -79.545725)
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        
        mapView.setRegion(region, animated: true)
        
        let gestureRecognizer = UITapGestureRecognizer(target: self, action:#selector(MapViewController.handleTap(_:)))
        gestureRecognizer.delegate = self
        mapView.addGestureRecognizer(gestureRecognizer)

        getMapObjects()
    }

    
    func handleTap(gestureReconizer: UITapGestureRecognizer) {
        let location = gestureReconizer.locationInView(mapView)
        let coordinate = mapView.convertPoint(location,toCoordinateFromView: mapView)
        PokemonService.sharedInstance.updateLocation(coordinate.latitude, long: coordinate.longitude)
        updatePlayerLocation()
        
    }
    
    func updatePlayerLocation() {
        PokemonService.sharedInstance.updateLocation({
            response, status in
            if (status! == .Success){
                let parsedResponse = response?.subresponses as! [Pogoprotos.Networking.Responses.PlayerUpdateResponse]
                print(parsedResponse)
                for mapCell in parsedResponse {
                    for pokemon in mapCell.wildPokemons {
                        print(pokemon.pokemonData.pokemonId)
                    }
                }
                for mapCell in parsedResponse {
                    for fort in mapCell.forts {
                        print(fort.types.toString())
                    }
                }
            }
        })
    }
    
    
    func getMapObjects() {
        PokemonService.sharedInstance.getMapObjects({
            response, status in
            if (status! == .Success){
                let responseMapCells = response!.subresponses as! [Pogoprotos.Networking.Responses.GetMapObjectsResponse]
                self.getAllPokemonsInAnArrayWithObjectRespose(responseMapCells)
            }
        })
    }
    
    func getAllPokemonsInAnArrayWithObjectRespose(responseMapCells: [Pogoprotos.Networking.Responses.GetMapObjectsResponse]) {
        for responseCell in responseMapCells {
            for mapCell in responseCell.mapCells {

                for pokemon in mapCell.catchablePokemons {
                    print(pokemon.pokemonId)
                    addToMap(pokemon.latitude, long: pokemon.longitude, title: pokemon.pokemonId.toString())
                }
                for pokemon in mapCell.wildPokemons {
                    print(pokemon.pokemonData.pokemonId)
                    addToMap(pokemon.latitude, long: pokemon.longitude, title: pokemon.pokemonData.pokemonId.toString())
                }
                for pokemon in mapCell.nearbyPokemons {
                    print(pokemon.pokemonId)
//                    addToMap(pokemon., long: pokemon.longitude, title: pokemon.pokemonId.toString())
                }
                for fort in mapCell.forts {
                    print(fort.types.toString())
                    addToMap(fort.latitude, long: fort.longitude, title: fort.types.toString())
                }
            }
        }
    }
    
    
    
    func updateMapWithAllPokemons(){
        
    }
    
    func addToMap(lat:Double, long: Double, title: String) {
        // Drop a pin
        let dropPin = MKPointAnnotation()
        dropPin.coordinate = CLLocationCoordinate2DMake(lat, long)
        dropPin.title = title
        mapView.addAnnotation(dropPin)
    }

}

