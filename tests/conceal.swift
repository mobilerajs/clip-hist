import AppKit
let pb = NSPasteboard.general
pb.clearContents()
pb.setString("super-secret-password", forType: .string)
pb.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
