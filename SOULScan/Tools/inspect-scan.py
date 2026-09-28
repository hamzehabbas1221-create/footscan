#!/usr/bin/env python3
"""Inspect a SOUL export and optionally make an explicitly millimetre-scaled PLY.
Usage: python3 Tools/inspect-scan.py scan.zip [--millimetres model-mm.ply]
Standard library only. Does not extract archives or reconstruct missing surfaces.
"""
import argparse,json,math,struct,zipfile
from pathlib import Path

def ply(data):
    marker=b'end_header\n';offset=data.find(marker)
    if offset<0 or offset>16384:raise ValueError('Invalid PLY header')
    offset+=len(marker);header=data[:offset].decode('ascii')
    if 'format binary_little_endian 1.0' not in header:raise ValueError('Expected binary little-endian PLY')
    count=int(next(line for line in header.splitlines() if line.startswith('element vertex ')).split()[-1])
    if count<0 or count>100_000 or len(data)-offset!=count*12:raise ValueError('Invalid PLY point count or payload')
    points=list(struct.iter_unpack('<fff',data[offset:]))
    if not all(math.isfinite(v) for p in points for v in p):raise ValueError('Nonfinite model vertices')
    return points

def inspect(path,mm=None):
    with zipfile.ZipFile(path) as archive:
        entries=archive.infolist()
        if len(entries)>400 or sum(x.file_size for x in entries)>512*1024*1024:raise ValueError('Archive exceeds SOUL limits')
        if len({x.filename for x in entries})!=len(entries):raise ValueError('Duplicate archive names')
        if archive.testzip() is not None:raise ValueError('Archive CRC check failed')
        record=json.loads(archive.read('scan.json'));frames=json.loads(archive.read('frames.json'));points=ply(archive.read('model.ply'))
        if record['schemaVersion']!=1:raise ValueError('Unsupported scan schema')
        if len(points)!=record['pointCount'] or len(frames)!=record['acceptedFrames']:raise ValueError('Counts do not match metadata')
        for frame in frames:
            matrix=frame['poseRowMajor'];cal=frame['calibration']
            if len(matrix)!=16 or not all(math.isfinite(x) for x in matrix) or matrix[12:]!=[0,0,0,1]:raise ValueError('Invalid frame pose')
            expected=cal['depthWidth']*cal['depthHeight']*4
            if archive.getinfo(frame['depthFile']).file_size!=expected:raise ValueError('Raw depth dimensions do not match')
            ply(archive.read(frame['pointFile']))
        bounds=[(max(p[i] for p in points)-min(p[i] for p in points))*1000 for i in range(3)]
        print(json.dumps({'side':record['side'],'reference':record['reference'],'points':len(points),'accepted_frames':len(frames),'cloud_bounds_mm':bounds,'mean_ICP_residual_mm':record['averageResidualMM'],'manufacturing_validated':False},indent=2))
        if mm:
            output=Path(mm)
            if output.resolve()==Path(path).resolve():raise ValueError('Output cannot replace input archive')
            header=f'ply\nformat binary_little_endian 1.0\ncomment units millimetres; UNVALIDATED SURFACE SCAN\nelement vertex {len(points)}\nproperty float x\nproperty float y\nproperty float z\nend_header\n'.encode()
            with output.open('xb') as file:
                file.write(header)
                for p in points:file.write(struct.pack('<fff',*(v*1000 for v in p)))
            print(f'Wrote {output} in millimetres. This is a point cloud, not a mesh or printable footbed.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('archive');parser.add_argument('--millimetres',type=Path);args=parser.parse_args()
    try:inspect(args.archive,args.millimetres)
    except (OSError,ValueError,KeyError,StopIteration,zipfile.BadZipFile) as error:parser.exit(1,f'Cannot read scan: {error}\n')
