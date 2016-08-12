//
//  LoginViewController.swift
//  PGoApi
//
//  Created by Harsh Singh on 2016-08-11.
//  Copyright © 2016 CocoaPods. All rights reserved.
//

import UIKit
import PGoApi


class LoginViewController: UIViewController, PGoAuthDelegate {
    
    var googleAuth: GPSOAuth!
    var ptcAuth: PtcOAuth!


    @IBOutlet var segmentControl: UISegmentedControl!
    @IBOutlet var passwordTextField: UITextField!
    @IBOutlet var usernameTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //populate username password
        enterCredentialsIfAlreadySaved()
    }
    
    func didReceiveAuth() {
        //Set user defaults
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.setValue(usernameTextField.text!, forKey: "username")
        defaults.setValue(passwordTextField.text!, forKey: "password")
        defaults.setInteger(segmentControl.selectedSegmentIndex, forKey: "loginAccountType")
        defaults.synchronize()
        
        //set singleton auth 
        PokemonService.sharedInstance.auth = segmentControl.selectedSegmentIndex == 0 ? ptcAuth : googleAuth
        PokemonService.sharedInstance.login({
            response, status in
            if status == .Success{
                //perform segue
                self.performSegueWithIdentifier("loginToHome", sender: nil)
            }
            else {
                self.showLoginFailureAlert()
            }
        })
    }
    
    func didNotReceiveAuth() {
        showLoginFailureAlert()
    }
    
    
    
    @IBAction func Login(sender: UIButton) {
        
        if let text = usernameTextField.text {
            print(text)
        }
        
        if areTextFieldsEmpty() {
            let alertController = UIAlertController(title: "Username or password not entered", message: "Don't try to be clever, we need the username and the password to login for you.", preferredStyle: .Alert)
            let alertAction = UIAlertAction(title: "ok", style: .Default, handler: {
                action in
                alertController.dismissViewControllerAnimated(true, completion: nil)
            })
            alertController.addAction(alertAction)
            presentViewController(alertController, animated: true, completion: nil)
            return
        }
        
        if segmentControl.selectedSegmentIndex == 0 {
            //PTC
            loginWithPTC()
        }
        else if segmentControl.selectedSegmentIndex == 1 {
            //GOOGLE
            loginWithGoogle()
        }
  
    }
    
    func loginWithPTC() {
        ptcAuth = PtcOAuth()
        ptcAuth.delegate = self
        ptcAuth.login(withUsername: usernameTextField.text!, withPassword: passwordTextField.text!)
    }
    
    func loginWithGoogle() {
        googleAuth = GPSOAuth()
        googleAuth.delegate = self
        googleAuth.login(withUsername: usernameTextField.text!, withPassword: passwordTextField.text!)
    }
    
    func areTextFieldsEmpty() -> Bool {
        return usernameTextField.text?.characters.count == 0 && passwordTextField.text?.characters.count == 0
    }
    
    func enterCredentialsIfAlreadySaved() {
        let defaults = NSUserDefaults.standardUserDefaults()
        usernameTextField.text = defaults.stringForKey("username")
        passwordTextField.text = defaults.stringForKey("password")
        segmentControl.selectedSegmentIndex = defaults.integerForKey("loginAccountType")
    }
    
    func showLoginFailureAlert() {
        let alertController = UIAlertController(title: "Error!", message: "Failed to login.\nPlease check your credentials and type of login you are trying to attempt.", preferredStyle: .Alert)
        let alertAction = UIAlertAction(title: "ok", style: .Default, handler: {
            action in
//            alertController.dismissViewControllerAnimated(true, completion: nil)
        })
        alertController.addAction(alertAction)
        presentViewController(alertController, animated: true, completion: nil)

        
        
    }
    

}
