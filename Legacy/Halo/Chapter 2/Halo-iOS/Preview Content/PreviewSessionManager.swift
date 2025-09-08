//
//  PreviewSessionManager.swift
//  Halo-iOS
//
//  Created by Cyril Zakka on 3/17/25.
//

import Foundation
import SwiftUI
import AccessorySetupKit


class MockASAccessory: ASAccessory, @unchecked Sendable {
    private var _displayName: String
    private var _state: ASAccessory.AccessoryState
    private var _descriptor: ASDiscoveryDescriptor
    
    override var displayName: String {
        return _displayName
    }
    
    override var state: ASAccessory.AccessoryState {
        return _state
    }
    
    override var descriptor: ASDiscoveryDescriptor {
        return _descriptor
    }
    
    init(displayName: String) {
        // Create a basic descriptor - you may need to adjust this
        let descriptor = ASDiscoveryDescriptor()
        
        self._displayName = displayName
        self._state = .authorized // Assuming this is one of the states
        self._descriptor = descriptor
        
        super.init()
    }
    
    static var previewRing: MockASAccessory {
        return MockASAccessory(displayName: "Preview Ring")
    }
}

// For preview purposes
class PreviewRingSessionManager: RingSessionManager {
    override init() {
        super.init()
        self.pickerDismissed = true
        self.currentRing = MockASAccessory.previewRing
    }
}
