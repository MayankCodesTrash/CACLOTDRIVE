import SwiftUI

/// The user's cover photo if they attached one, otherwise generated road artwork.
struct DriveArtwork: View {
    let photo: Data?
    let scene: SceneStyle
    let seed: Int

    init(drive: Drive) {
        photo = drive.coverPhoto
        scene = drive.scene
        seed = drive.sceneSeed
    }

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            SceneArt(style: scene, seed: seed)
        }
    }
}
