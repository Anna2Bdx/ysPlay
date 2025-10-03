//
//  EZPlayerView.swift
//  Runner
//
//  Created by 潇洒的然然 on 2022/12/01.
//

import Foundation
import Flutter
import UIKit

class YsPlayView: NSObject, FlutterPlatformView{
   
    func view() -> UIView {
        // Instancier la vue de lecture
        let uiView = UIView()
        
        // Envoyer une notification, transmettre l'uiview à [SwiftYsPlayPlugin]
        let notification = Notification(name: Notification.Name.init("video_view"),object: uiView)
        NotificationCenter.default.post(notification)
        return uiView
    }
    
   
    
    

    
        
    
    
   

    
    
}
