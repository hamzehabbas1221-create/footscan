import contextlib,importlib.util,io,json,struct,tempfile,unittest,zipfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('inspector',Path(__file__).resolve().parents[1]/'Tools/inspect-scan.py')
inspector=importlib.util.module_from_spec(spec);spec.loader.exec_module(inspector)

class InspectorTests(unittest.TestCase):
 def fixture(self,path):
  header=b'ply\nformat binary_little_endian 1.0\nelement vertex 2\nproperty float x\nproperty float y\nproperty float z\nend_header\n'
  body=header+struct.pack('<ffffff',0,0,-.3,.1,.2,-.35)
  record={'schemaVersion':1,'pointCount':2,'acceptedFrames':1,'side':'Left','reference':'TEST','averageResidualMM':0}
  frames=[{'poseRowMajor':[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],'calibration':{'depthWidth':2,'depthHeight':1},'depthFile':'frame.depth-f32','pointFile':'frame.ply'}]
  with zipfile.ZipFile(path,'w') as z:
   z.writestr('model.ply',body);z.writestr('scan.json',json.dumps(record));z.writestr('frames.json',json.dumps(frames));z.writestr('frame.ply',body);z.writestr('frame.depth-f32',struct.pack('<ff',.3,.35))
 def test_archive_and_explicit_mm_conversion(self):
  with tempfile.TemporaryDirectory() as d:
   archive=Path(d)/'scan.zip';output=Path(d)/'mm.ply';self.fixture(archive)
   with contextlib.redirect_stdout(io.StringIO()):inspector.inspect(archive,output)
   p=inspector.ply(output.read_bytes());self.assertAlmostEqual(p[1][0],100,places=4);self.assertAlmostEqual(p[1][1],200,places=4);self.assertAlmostEqual(p[0][2],-300,places=3)
   with contextlib.redirect_stdout(io.StringIO()),self.assertRaises(FileExistsError):inspector.inspect(archive,output)
 def test_reject_truncated_ply(self):
  with self.assertRaises(ValueError):inspector.ply(b'ply\nformat binary_little_endian 1.0\nelement vertex 5\nend_header\n')
 def test_reject_nonfinite_coordinates(self):
  with self.assertRaises(ValueError):inspector.ply(b'ply\nformat binary_little_endian 1.0\nelement vertex 1\nend_header\n'+struct.pack('<fff',float('nan'),0,0))

if __name__=='__main__':unittest.main()
