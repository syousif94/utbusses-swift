//
//  MapViewController.swift
//  Park@Mine
//
//  Created by Sammy Yousif on 2/10/16.
//  Copyright © 2016 Sammy Yousif. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit
import Firebase

class MapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {
    
    @IBOutlet weak var map: MKMapView!
    @IBAction func gotOnBtn(sender: AnyObject) {
        switch CLLocationManager.authorizationStatus() {
        case .AuthorizedWhenInUse:
            checkInOnBus()
        case .NotDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .Denied, .Restricted:
            if let appSettings = NSURL(string: UIApplicationOpenSettingsURLString) {
                UIApplication.sharedApplication().openURL(appSettings)
            }
        default:
            break
        }
        
        locationManager.requestWhenInUseAuthorization()
    }
    
    let minDistanceFromStop: Double = 50
    
    func checkInOnBus() {
        let deviceTime = NSDate().timeIntervalSince1970 * 1000
        let location = self.locationManager.location
        if let l = location {
            /*
            if l.horizontalAccuracy > minDistanceFromStop {
                return
            }*/
            let distances = wcStops.filter() { (coords: CLLocationCoordinate2D) in
                let stop = CLLocation(latitude: coords.latitude, longitude: coords.longitude)
                let distance = l.distanceFromLocation(stop)
                if distance <= minDistanceFromStop {
                    return true
                }
                return false
            }
            if distances.count < 1 {
                return
            }
            let checkInRef = wcDataRef.childByAutoId()
            let kFirebaseServerValueTimestamp = [".sv":"timestamp"]
            let checkIn = ["deviceTime": deviceTime, "timestamp": kFirebaseServerValueTimestamp]
            checkInRef.setValue(checkIn, withCompletionBlock: {
                (error:NSError?, ref:Firebase!) in
                if (error != nil) {
                    print("Data could not be saved.")
                } else {
                    self.geoFire.setLocation(l, forKey: checkInRef.key)
                }
            })
        }
    }
    
    var locationManager: CLLocationManager!
    
    var timer: NSTimer?
    
    var spots = [String:SpotAnnotation]()
    
    var firebaseRef = Firebase(url:"https://utbusses.firebaseio.com")
    
    var wcDataRef : Firebase {
        return firebaseRef.childByAppendingPath("wcdata")
    }
    
    var geoFireRef : Firebase {
        return firebaseRef.childByAppendingPath("wc")
    }
    
    var geoFire : GeoFire {
        return GeoFire(firebaseRef: geoFireRef)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = 1
        
        map.delegate = self
        map.showsPointsOfInterest = false
        if CLLocationManager.authorizationStatus() == .AuthorizedWhenInUse {
            map.showsUserLocation = true
        }
        
        let location = CLLocationCoordinate2D(
            latitude: 30.286390,
            longitude: -97.740726
        )
        
        let span = MKCoordinateSpanMake(0.022, 0.022)
        let region = MKCoordinateRegion(center: location, span: span)
        map.setRegion(region, animated: true)
        
        let coordinates: [CLLocationCoordinate2D]? = decodePolyline("mgzwDrqosQuD@gBL{CfCSNe@T}@VYBm@A[vLSjFMxEwL]Q`FIv@CbDI|HhHZ?@MpC?AI`DKzD?@GbCA~A??QjEvDTdBD~F\\lCJp@FdDLpDTT_ITwHNgERqENyEnFRJaFPeFF_CZuHf@oRJu@uCGoG}@eDa@")
        let pointer: UnsafeMutablePointer<CLLocationCoordinate2D> = UnsafeMutablePointer(coordinates!)
        let polyline = MKPolyline(coordinates: pointer, count: coordinates!.count)
        map.addOverlay(polyline)
        
        for annotation in stopAnnotations {
            self.map.addAnnotation(annotation)
        }
        
        // Query location by region
        let center = CLLocation(latitude: 30.286267, longitude: -97.742528)
        let query = geoFire.queryAtLocation(center, withRadius: 3500)
        
        query.observeEventType(.KeyEntered, withBlock: { (key: String!, location: CLLocation!) in
            self.wcDataRef.childByAppendingPath(key).observeSingleEventOfType(.Value, withBlock: { snapshot in
                let deviceTime = snapshot.childSnapshotForPath("deviceTime").value as! Double
                let serverTime = snapshot.childSnapshotForPath("timestamp").value as! Double
                let spot = SpotDatum(location: location, deviceTime: deviceTime, serverTime: serverTime)
                let annotation = SpotAnnotation(type: "user", location: spot.location, time: spot.deviceTime)
                self.spots[key] = annotation
                self.map.addAnnotation(annotation)
            })
        })
        
        query.observeEventType(.KeyExited, withBlock: { (key: String!, location: CLLocation!) in
            if let annotation = self.spots[key] {
                self.map.removeAnnotation(annotation)
                self.spots[key] = nil
            }
        })
        
        dispatch_async(dispatch_get_main_queue()) {
            self.timer = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: "refreshPinBackgrounds", userInfo: nil, repeats: true)
        }
    }
    
    func refreshPinBackgrounds() {
        for (_, annotation) in spots {
            let a: SpotAnnotation = annotation
            if a.type == "user" {
                let annotationView = map.viewForAnnotation(annotation) as? SpotAnnotationView
                if let av = annotationView {
                    av.refresh()
                }
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Location Manager Delegate Methods
    
    func locationManager(manager: CLLocationManager,
        didChangeAuthorizationStatus status: CLAuthorizationStatus)
    {
        switch status {
        case .AuthorizedWhenInUse:
            map.showsUserLocation = true
        case .Denied:
            map.showsUserLocation = false
        default:
            break
        }
    }
    
    // MARK: - Map Delegate Methods
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }
        var v : MKAnnotationView! = nil
        if annotation is SpotAnnotation {
            let a = annotation as! SpotAnnotation
            let ident:String = a.type
            //v = mapView.dequeueReusableAnnotationViewWithIdentifier(a.type)
            if v == nil {
                if ident == "user" {
                    v = SpotAnnotationView(annotation:annotation, reuseIdentifier:ident)
                }
                else if ident == "stop" {
                    v = BusStopAnnotationView(annotation:annotation, reuseIdentifier:ident)
                }
            }
        }
        v.annotation = annotation
        return v
    }
    
    func mapView(mapView: MKMapView, rendererForOverlay overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let polylineRenderer = MKPolylineRenderer(overlay: overlay)
            polylineRenderer.strokeColor = UTBussesStyles.routeBlue
            polylineRenderer.lineWidth = 5
            return polylineRenderer
        }
        
        let v : MKOverlayRenderer! = nil
        return v
    }
    

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
