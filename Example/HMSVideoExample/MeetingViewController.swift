//
//  MeetingViewController.swift
//  HMSVideo
//
//  Copyright (c) 2020 100ms. All rights reserved.
//

import UIKit
import HMSVideo

class MeetingViewController: UIViewController {
    @IBOutlet weak var collectionView: UICollectionView!

    var client: HMSClient!
    var roomName: String!
    var userName: String!
 
    var videoTrack: HMSVideoTrack?
    var localAudioTrack: HMSAudioTrack?
    var localVideoTrack: HMSVideoTrack?
    var videoCapturer: HMSVideoCapturer?
    var videoTracks = [HMSVideoTrack]()
    var localStream: HMSStream?
    var remoteStreams = [HMSStream]()
    var room: HMSRoom!
    
    var token: String?
    let tokenServerURL: String = "Insert sample token server url here"
    let endpointURL: String = "wss://prod-in.100ms.live/ws"
    
    var peerId = UUID().uuidString
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        fetchToken { [weak self] (token) in
            DispatchQueue.main.async {
                self?.token = token
                if (token == nil) {
                    self?.showTokenFailedError()
                } else {
                    self?.connect()
                }
            }
        }
    }
        
    
    func connect() {
        guard let token = token else { return }
        let peer = HMSPeer(name: userName, authToken: token)

        let config = HMSClientConfig()
        config.endpoint = endpointURL

        client = HMSClient(peer: peer, config: config)
        client.logLevel = HMSLogLevel.verbose
        
        self.room = HMSRoom(roomId: roomName)
        
        collectionView.register(VideoCollectionViewCell.self, forCellWithReuseIdentifier: "videoCell")
        
        client.onPeerJoin = { (room, peer) in
            // update UI if needed
        }
        
        client.onPeerLeave = { (room, peer) in
            // update UI if needed
        }
        
        client.onStreamAdd = { [weak self] (room, peer, streamInfo)  in
            DispatchQueue.main.async {
                self?.subscribe(room: room, peer: peer, streamInfo: streamInfo)
            }
        }
        
        client.onStreamRemove = { [weak self] (room, peer, streamInfo)  in
            DispatchQueue.main.async {
                self?.removeVideoTrack(for: streamInfo.streamId)
            }
        }
        
        client.onBroadcast = { (room, peer, message) in
            // update UI if needed
        }
        
        client.onConnect = { [weak self] in
            DispatchQueue.main.async {
                self?.join()
            }
        }
        
        client.onDisconnect = { [weak self] error in
            DispatchQueue.main.async {
                self?.showDisconnectError(error)
            }
        }
        

        client.connect()
    }
    
    func showDisconnectError(_ error: Error?) {
        let alertController = UIAlertController(title: "Error", message: "Connection lost: \(error?.localizedDescription ?? "Unknown")", preferredStyle: .alert)
                
        let action1 = UIAlertAction(title: "OK", style: .default)
        alertController.addAction(action1)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func showTokenFailedError() {
        let alertController = UIAlertController(title: "Error", message: "Could not fetch token.", preferredStyle: .alert)
                
        let action1 = UIAlertAction(title: "OK", style: .default)
        alertController.addAction(action1)
        self.present(alertController, animated: true, completion: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if isMovingFromParent {
            UIApplication.shared.isIdleTimerDisabled = false
            cleanup()
        }
    }
    
    func publish() {
        let constraints = HMSMediaStreamConstraints()
        constraints.shouldPublishAudio = true
        constraints.shouldPublishVideo = true
        constraints.codec = .VP8
        constraints.bitrate = 256
        constraints.frameRate = 25
        constraints.resolution = .QVGA

        guard let localStream = try? client.getLocalStream(constraints) else {
            return;
        }
        
        client.publish(localStream, room: room, completion: { [weak self] (stream, error) in
            guard let stream = stream else { return }
            
            DispatchQueue.main.async {
                self?.setupLocalStream(stream: stream)
            }
        })
    }
    
    func setupLocalStream(stream: HMSStream) {
        localStream = stream
        videoCapturer = stream.videoCapturer
        localAudioTrack = stream.audioTracks?.first
        localVideoTrack = stream.videoTracks?.first
        
        videoCapturer?.startCapture()
        if let track = localVideoTrack {
            addVideoTrack(track)
        }
    }
    
    func subscribe(room: HMSRoom, peer: HMSPeer, streamInfo: HMSStreamInfo) {
        client.subscribe(streamInfo, room: room, completion: { [weak self]  (stream, error) in
            DispatchQueue.main.async {
                guard let stream = stream else { return }
                self?.remoteStreams.append(stream)

                guard let videoTrack = stream.videoTracks?.first else { return }
                self?.addVideoTrack(videoTrack)
            }
        })
    }
    
    func join() {
        client.join(room, completion: { [weak self] (success, error) in
            self?.publish()
        })
    }
    
    func addVideoTrack(_ track: HMSVideoTrack) {
        videoTracks.append(track)
        collectionView.reloadData()
    }
    
    func removeVideoTrack(for streamId: String) {
        videoTracks.removeAll { $0.streamId == streamId }
        collectionView.reloadData()
    }
    
    @IBAction func micMute(_ sender: Any) {
        guard let track = self.localAudioTrack else { return }
        track.enabled = !track.enabled
    }
    
    @IBAction func videoMute(_ sender: Any) {
        guard let track = self.localVideoTrack else { return }
        track.enabled = !track.enabled
    }
    
    @IBAction func camSwitch(_ sender: Any) {
        guard let capturer = self.videoCapturer else { return }
        capturer.switchCamera()
    }
    
    func cleanup() {
        guard let client = client else {
            return
        }
        
        let dispatchGroup = DispatchGroup()
                
        if let localStream = localStream {
            dispatchGroup.enter()
            client.unpublish(localStream, room: room) { (success, error) in
                dispatchGroup.leave()
            }
        }
        
        remoteStreams.forEach { (stream) in
            dispatchGroup.enter()
            client.unsubscribe(stream, room: room) { (success, error) in
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.enter()
        client.leave(room) { (success, error) in
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            print("Cleanup done")
        }
    }
    
    func fetchToken(completion: @escaping (String?)->Void) {
        guard let endpointUrl = URL(string: endpointURL) else {
            completion(nil)
            return
        }

        guard let subDomain = endpointUrl.host?.components(separatedBy: ".").first else {
            completion(nil)
            return
        }
        
        
        let parameters = ["room_id": roomName,
                          "user_name": userName,
                          "role": "guest",
                          "env" : subDomain
        ]

        //create the url with URL
        guard let url = URL(string: tokenServerURL) else {
            completion(nil)
            return
        }

        //create the session object
        let session = URLSession.shared

        //now create the URLRequest object using the url object
        var request = URLRequest(url: url)
        request.httpMethod = "POST" //set http method as POST

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: .prettyPrinted) // pass dictionary to nsdata object and set it as request body
        } catch let error {
            print(error.localizedDescription)
            completion(nil)
            return
        }

        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        //create dataTask using the session object to send data to the server
        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in

            guard error == nil else {
                print("\(String(describing: error))")
                completion(nil)
                return
            }

            guard let data = data else {
                print("No data received")
                completion(nil)
                return
            }

            do {
                //create json object from data
                if let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                    if let token = json["token"] as? String {
                        completion(token)
                    } else {
                        completion(nil)
                    }
                }
            } catch let error {
                print(error.localizedDescription)
            }
        })
        task.resume()
    }
}

extension MeetingViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return videoTracks.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "videoCell", for: indexPath) as? VideoCollectionViewCell, indexPath.item < videoTracks.count else {
            return UICollectionViewCell()
        }
        let track = videoTracks[indexPath.item]
        
        cell.videoView.setVideoTrack(track)
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var result = CGSize.zero
        
        result.width = floor(collectionView.frame.size.width / 2.0)
        result.height = floor(collectionView.frame.size.height / 2.0)

        return result
    }
}
