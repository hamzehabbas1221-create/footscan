import SwiftUI

@main
struct SOULScanApp: App {
    @StateObject private var store=ScanStorage()
    var body: some Scene { WindowGroup { HomeView().environmentObject(store).tint(.primary).preferredColorScheme(.light) } }
}

struct SoulButton: View {
    let title: String
    var symbol="arrow.up.right"
    var light=false
    var disabled=false
    let action: () -> Void
    var body: some View {
        Button(action:action) { HStack { Text(title).fontWeight(.semibold);Spacer();Image(systemName:symbol) }.padding(20).frame(maxWidth:.infinity).background(light ? Color.white : Color.black).foregroundStyle(light ? Color.black : Color.white).opacity(disabled ? 0.4 : 1).clipShape(RoundedRectangle(cornerRadius:16)) }.disabled(disabled)
    }
}
struct Eyebrow: View { let text:String;var body:some View{Text(text.uppercased()).font(.system(size:12,weight:.semibold,design:.monospaced)).tracking(1.5).foregroundStyle(.secondary)} }
struct HomeView: View {
    @EnvironmentObject var store:ScanStorage
    @State private var setup=false
    @State private var guide=false
    @State private var recordToDelete:ScanRecord?
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:28) {
                    HStack { Image("SoulLogo").resizable().scaledToFit().frame(width:116,height:35);Spacer();Text("SCAN").font(.system(size:12,weight:.medium,design:.monospaced)).tracking(3) }.padding(.top,8)
                    VStack(alignment:.leading,spacing:14) { Eyebrow(text:"YOUR FOOTPRINT. YOUR FOUNDATION.");Text("Made\naround you.").font(.system(size:58,weight:.semibold)).tracking(-3).lineSpacing(-6);Text("Capture your feet in 3D. Keep your scans.\nBuild from your own shape.").font(.body).foregroundStyle(.secondary) }
                    VStack(alignment:.leading,spacing:22) {
                        HStack { Image(systemName:"viewfinder").font(.system(size:40,weight:.ultraLight));Spacer();Text("01 / CAPTURE").font(.system(size:12,design:.monospaced)) }
                        Text("A personal\nstarting point.").font(.system(size:32,weight:.medium)).tracking(-1)
                        Text("Front TrueDepth camera · On-device processing").font(.system(size:13)).foregroundStyle(.white.opacity(0.65))
                        SoulButton(title:"Start a foot scan",symbol:"plus",light:true,disabled:!DepthCamera.isSupported){setup=true}
                    }.padding(25).background(Color(white:0.07)).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius:24))
                    if !DepthCamera.isSupported { Label("Capture requires an iPhone with a front TrueDepth camera. Saved scans can still be reviewed here.",systemImage:"camera.fill").font(.footnote).foregroundStyle(.secondary) }
                    Button { guide=true } label: { HStack(spacing:14) { Image(systemName:"questionmark.circle").font(.title2);VStack(alignment:.leading,spacing:4){Text("Before your first scan").fontWeight(.medium);Text("Position, lighting and a steady foot.").font(.footnote).foregroundStyle(.secondary)};Spacer();Image(systemName:"arrow.up.right") }.padding(18).background(Color(white:0.95)).clipShape(RoundedRectangle(cornerRadius:16)) }.buttonStyle(.plain)
                    HStack { Text("Your scans").font(.title2.weight(.semibold));Spacer();Text("\(store.records.count)").foregroundStyle(.secondary) }
                    if store.records.isEmpty { VStack(alignment:.leading,spacing:8){Text("Your first pair starts here.").fontWeight(.medium);Text("Left and right scans are saved separately, privately on this phone.").font(.subheadline).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(22).overlay(RoundedRectangle(cornerRadius:16).stroke(Color.gray.opacity(0.25))) }
                    ForEach(store.records) { record in
                        NavigationLink { ReviewView(record:record) } label: { HStack(spacing:15) { Image(systemName:"shoeprints.fill").font(.title2).frame(width:50,height:55).background(Color(white:0.94)).clipShape(RoundedRectangle(cornerRadius:12));VStack(alignment:.leading,spacing:4){Text(record.title).fontWeight(.semibold);Text("\(record.activity) · \(record.createdAt.formatted(date:.abbreviated,time:.omitted))").font(.footnote).foregroundStyle(.secondary)};Spacer();Image(systemName:"chevron.right").font(.footnote) }.padding(.vertical,8) }.buttonStyle(.plain).contextMenu{Button("Delete scan",role:.destructive){recordToDelete=record}}
                    }
                    Text("PROTOTYPE / Scans require scale, coverage and fit validation before manufacturing.").font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary).padding(.vertical,10)
                }.padding(24)
            }.background(.white).toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$setup){SetupView()}
            .sheet(isPresented:$guide){GuideView()}
            .confirmationDialog("Delete this scan and its captured depth files?",isPresented:Binding(get:{recordToDelete != nil},set:{if !$0{recordToDelete=nil}}),titleVisibility:.visible){Button("Delete scan",role:.destructive){if let r=recordToDelete {do{try store.delete(r)}catch{store.error=error.localizedDescription}};recordToDelete=nil}}
            .alert("Local storage",isPresented:Binding(get:{store.error != nil},set:{if !$0{store.error=nil}})){Button("OK",role:.cancel){store.error=nil}}message:{Text(store.error ?? "")}
        }
    }
}
struct GuideView:View {
    @Environment(\.dismiss) var dismiss
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:26){Eyebrow(text:"A GOOD SCAN STARTS HERE");Text("Still foot.\nSlow camera.").font(.system(size:43,weight:.semibold)).tracking(-2)
        instruction("01","Expose the sole","Sit with your leg comfortably supported and your bare foot held still in the air. The sole must be visible. A standing scan cannot see the underside of your foot.")
        instruction("02","Ask someone to help","The front camera faces your foot, so the screen faces away from the operator. Voice cues and a countdown help a second person move the phone safely.")
        instruction("03","Start 25–45 cm away","Use soft indoor light. Keep the whole foot in view, with clear space behind it. Avoid direct sunlight, shiny surfaces and a hand touching the scan area.")
        instruction("04","Follow a shallow arc","Start at the sole. Move slowly toward the inner arch, heel and outer edge with plenty of overlapping views. Keep the foot in exactly the same position. Pause if you lose alignment.")
        instruction("05","Review before you export","Look for doubled surfaces, background objects or missing heel, arch and toe areas. This prototype does not automatically identify the foot or certify a complete scan.")
        SoulButton(title:"Ready when you are",symbol:"checkmark"){dismiss()}
    }.padding(25)}.navigationTitle("Scan guide").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarTrailing){Button("Done"){dismiss()}}}}}
    private func instruction(_ n:String,_ title:String,_ body:String)->some View{HStack(alignment:.top,spacing:16){Text(n).font(.system(size:14,design:.monospaced)).foregroundStyle(.secondary);VStack(alignment:.leading,spacing:8){Text(title).font(.title3.weight(.semibold));Text(body).foregroundStyle(.secondary)}}}
}
struct SetupView:View {
    @EnvironmentObject var store:ScanStorage
    @Environment(\.dismiss) var dismiss
    @State private var side:FootSide = .left
    @State private var activity="Everyday"
    @State private var reference=""
    @State private var showCapture=false
    @State private var showGuide=false
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:28){Eyebrow(text:"ONE FOOT AT A TIME");Text("Let’s find\nyour shape.").font(.system(size:45,weight:.semibold)).tracking(-2)
        VStack(alignment:.leading,spacing:12){Text("Which foot?").fontWeight(.medium);Picker("Foot",selection:$side){ForEach(FootSide.allCases){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)}
        VStack(alignment:.leading,spacing:12){Text("Made for your move").fontWeight(.medium);Picker("Activity",selection:$activity){ForEach(["Everyday","Run","Hike","Bike","Ski"],id:\.self){Text($0)}}.pickerStyle(.menu).frame(maxWidth:.infinity,alignment:.leading).padding(10).background(Color(white:0.95)).clipShape(RoundedRectangle(cornerRadius:12))}
        VStack(alignment:.leading,spacing:12){Text("Reference (optional)").fontWeight(.medium);TextField("A client code or fitting reference",text:$reference).textInputAutocapitalization(.characters).autocorrectionDisabled().padding(16).background(Color(white:0.95)).clipShape(RoundedRectangle(cornerRadius:12)).onChange(of:reference){_,value in if value.count>40{reference=String(value.prefix(40))}}}
        Label("Depth data stays on this phone. Export it only when you choose.",systemImage:"lock").font(.subheadline).foregroundStyle(.secondary)
        Button("Read the positioning guide"){showGuide=true}.underline()
        SoulButton(title:"Open the scanner",symbol:"viewfinder"){showCapture=true}
    }.padding(25)}.navigationTitle("New scan").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.topBarLeading){Button("Cancel"){dismiss()}}}.fullScreenCover(isPresented:$showCapture,onDismiss:{store.refresh();dismiss()}){CaptureView(root:store.root,side:side,activity:activity,reference:reference)}.sheet(isPresented:$showGuide){GuideView()}}}
}
