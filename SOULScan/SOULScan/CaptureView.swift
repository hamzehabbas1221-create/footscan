import SwiftUI
import UIKit

struct CaptureView:View {
    @EnvironmentObject var store:ScanStorage
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var controller:ScanController
    @State private var confirmExit=false
    let side:FootSide
    init(root:URL,side:FootSide,activity:String,reference:String){self.side=side;_controller=StateObject(wrappedValue:ScanController(root:root,side:side,activity:activity,reference:reference))}
    var body:some View {
        Group {
            if let saved=controller.saved {
                NavigationStack{ReviewView(record:saved).toolbar{ToolbarItem(placement:.topBarTrailing){Button("Done"){dismiss()}}}}
            } else {
                VStack(spacing:0){
                    HStack{Button{confirmExit=true}label:{Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityLabel("Exit scan");Spacer();VStack(spacing:3){Text("\(side.rawValue.uppercased()) FOOT").font(.system(size:12,weight:.semibold,design:.monospaced)).tracking(2);Text(controller.snapshot.isRecording ? "CAPTURING DEPTH" : "POSITION YOUR FOOT").font(.system(size:10,design:.monospaced)).foregroundStyle(.white.opacity(0.5))};Spacer();Image(systemName:"lock").frame(width:44,height:44).foregroundStyle(.white.opacity(0.6))}.padding(.horizontal,12)
                    ZStack {
                        PointCloudView(points:controller.snapshot.points)
                        if controller.snapshot.points.isEmpty{VStack(spacing:18){Image(systemName:"viewfinder").font(.system(size:85,weight:.ultraLight));Text("Point the front camera\nat the sole of your foot.").multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.6))}}
                        VStack{HStack{Text(controller.snapshot.distanceCM>0 ? String(format:"%.0f CM",controller.snapshot.distanceCM) : "DEPTH —").font(.system(size:13,weight:.medium,design:.monospaced));Spacer();Text(controller.snapshot.isRecording ? String(format:"%02d:%02d",Int(controller.snapshot.elapsed)/60,Int(controller.snapshot.elapsed)%60) : "LIVE DEPTH").font(.system(size:13,design:.monospaced))}.padding(20);Spacer();if let countdown=controller.countdown{Text(String(countdown)).font(.system(size:96,weight:.thin)).frame(maxHeight:.infinity)};Text(controller.snapshot.status).font(.subheadline).multilineTextAlignment(.center).padding(16).frame(maxWidth:.infinity).background(Color.black.opacity(0.6))}
                    }.clipShape(RoundedRectangle(cornerRadius:22)).padding(.horizontal,14)
                    HStack(spacing:0){metric("POINTS",controller.snapshot.pointCount.formatted());metric("FRAMES",String(controller.snapshot.acceptedFrames));metric("VIEW BINS",String(controller.snapshot.viewBins))}.padding(.vertical,22)
                    VStack(spacing:12){
                        if controller.snapshot.isRecording{SoulButton(title:"Pause scan",symbol:"pause.fill",light:true){controller.pause()}}
                        else{SoulButton(title:controller.snapshot.acceptedFrames>0 ? "Resume scan" : "Begin scan",symbol:"record.circle",light:true,disabled:!controller.snapshot.canCapture || controller.countdown != nil || controller.finishing){controller.begin()}}
                        if controller.snapshot.acceptedFrames>0{Button{controller.finish()}label:{HStack{if controller.finishing{ProgressView().tint(.white)};Text(controller.finishing ? "Saving your scan…" : "Finish & review")}.frame(maxWidth:.infinity).padding(12)}.disabled(controller.finishing || controller.countdown != nil)}
                        Text("Keep the foot still. Move only the phone.").font(.system(size:12)).foregroundStyle(.white.opacity(0.5))
                    }.padding(.horizontal,24).padding(.bottom,20)
                }.background(Color(white:0.055)).foregroundStyle(.white)
            }
        }
        .onAppear{controller.startCamera();UIApplication.shared.isIdleTimerDisabled=true}
        .onDisappear{controller.suspend();UIApplication.shared.isIdleTimerDisabled=false}
        .onChange(of:scenePhase){_,phase in if phase != .active{controller.suspend();UIApplication.shared.isIdleTimerDisabled=false}else if controller.saved==nil{controller.startCamera();UIApplication.shared.isIdleTimerDisabled=true}}
        .onChange(of:controller.saved?.id){_,_ in store.refresh();UIApplication.shared.isIdleTimerDisabled=false}
        .confirmationDialog("Discard this unfinished scan?",isPresented:$confirmExit,titleVisibility:.visible){Button("Discard scan",role:.destructive){controller.discard();dismiss()};Button("Keep scanning",role:.cancel){}}
        .alert("Scan paused",isPresented:Binding(get:{controller.error != nil},set:{if !$0{controller.error=nil}})){Button("OK",role:.cancel){controller.error=nil};Button("Open Settings"){if let url=URL(string:UIApplication.openSettingsURLString){UIApplication.shared.open(url)}}}message:{Text(controller.error ?? "")}
    }
    private func metric(_ title:String,_ value:String)->some View{VStack(spacing:6){Text(value).font(.system(size:22,weight:.medium,design:.monospaced));Text(title).font(.system(size:10,design:.monospaced)).foregroundStyle(.white.opacity(0.5))}.frame(maxWidth:.infinity)}
}

struct ExportItem:Identifiable { let id=UUID();let url:URL }
struct ReviewView:View {
    let record:ScanRecord
    @EnvironmentObject var store:ScanStorage
    @State private var points:[SoulPoint]=[]
    @State private var error:String?
    @State private var exporting=false
    @State private var share:ExportItem?
    @State private var showDiagnostics=false
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:24){
            Eyebrow(text:"YOUR SHAPE / IN THREE DIMENSIONS")
            HStack(alignment:.firstTextBaseline){Text(record.title).font(.system(size:40,weight:.semibold)).tracking(-1.8);Spacer();Text(record.activity).font(.subheadline).foregroundStyle(.secondary)}
            ZStack(alignment:.bottom){PointCloudView(points:points,interactive:true).frame(height:350);Text("DRAG TO ROTATE · PINCH TO ZOOM").font(.system(size:10,design:.monospaced)).tracking(1).foregroundStyle(.white.opacity(0.65)).padding(16)}.clipShape(RoundedRectangle(cornerRadius:22))
            HStack{stat("Surface points",record.pointCount.formatted());Spacer();stat("Captured views",String(record.acceptedFrames));Spacer();stat("Foot",record.side.rawValue)}
            VStack(alignment:.leading,spacing:12){Label("Review required",systemImage:"viewfinder").font(.headline);Text("Check the heel, arch and toes. Look for gaps, duplicated surfaces or background objects before you use this scan.").font(.subheadline).foregroundStyle(.secondary);if record.acceptedFrames<10 || record.viewBins<3{Text("Limited viewpoints were captured. This may be a partial surface scan.").font(.subheadline.weight(.medium))};Text("A low alignment residual does not prove dimensional accuracy. This is not a production-approved footbed model.").font(.footnote).foregroundStyle(.secondary)}.padding(20).background(Color(white:0.95)).clipShape(RoundedRectangle(cornerRadius:16))
            SoulButton(title:exporting ? "Preparing your export…" : "Export scan package",symbol:"square.and.arrow.up",disabled:exporting || points.isEmpty){exportPackage()}
            Text("ZIP · 3D surface (PLY) · raw depth · calibration · frame alignment · scan details").font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Scan diagnostics",isExpanded:$showDiagnostics){VStack(alignment:.leading,spacing:12){diagnostic("Captured",record.createdAt.formatted(date:.abbreviated,time:.shortened));diagnostic("Reference",record.reference.isEmpty ? "None" : record.reference);diagnostic("Rejected frames",String(record.rejectedFrames));diagnostic("Azimuth view bins","\(record.viewBins) of 24");diagnostic("Mean ICP residual",String(format:"%.2f mm",record.averageResidualMM));diagnostic("Cloud bounds (not foot size)",record.boundsMM.map{String(format:"%.1f",$0)}.joined(separator:" × ")+" mm");Text("Bounds are aligned to the first camera frame. View bins indicate motion around one axis, not anatomical completeness. Exports use metres.").font(.footnote).foregroundStyle(.secondary)}.padding(.top,12)}
            Text("Saved on this phone · No automatic uploads").font(.footnote).foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.bottom,20)
        }.padding(24)}.background(.white).navigationTitle("Your scan").navigationBarTitleDisplayMode(.inline)
        .onAppear{if points.isEmpty{DispatchQueue.global(qos:.userInitiated).async{do{let loaded=try store.points(record);DispatchQueue.main.async{points=loaded}}catch{DispatchQueue.main.async{self.error=error.localizedDescription}}}}}
        .sheet(item:$share,onDismiss:{clearExports()}){item in ShareSheet(url:item.url)}
        .alert("Couldn’t open the scan",isPresented:Binding(get:{error != nil},set:{if !$0{error=nil}})){Button("OK",role:.cancel){error=nil}}message:{Text(error ?? "")}
    }
    private func stat(_ title:String,_ value:String)->some View{VStack(alignment:.leading,spacing:5){Text(value).font(.title3.weight(.semibold));Text(title).font(.system(size:12)).foregroundStyle(.secondary)}}
    private func diagnostic(_ label:String,_ value:String)->some View{HStack(alignment:.top){Text(label).foregroundStyle(.secondary);Spacer();Text(value).multilineTextAlignment(.trailing)}.font(.footnote)}
    private func exportPackage(){exporting=true;DispatchQueue.global(qos:.userInitiated).async{do{let url=try store.export(record);DispatchQueue.main.async{share=ExportItem(url:url);exporting=false}}catch{DispatchQueue.main.async{self.error=error.localizedDescription;exporting=false}}}}
    private func clearExports(){let folder=FileManager.default.temporaryDirectory.appendingPathComponent("SOUL-Exports");try? FileManager.default.removeItem(at:folder)}
}
struct ShareSheet:UIViewControllerRepresentable {
    let url:URL
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)}
    func updateUIViewController(_ uiViewController:UIActivityViewController,context:Context){}
}
