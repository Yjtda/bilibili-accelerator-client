import { open } from 'node:fs/promises';

const target = process.argv[2];
if (!target) throw new Error('Missing executable path');

const file = await open(target, 'r+');
try {
  const header = Buffer.alloc(4096);
  await file.read(header, 0, header.length, 0);
  const peOffset = header.readUInt32LE(0x3c);
  const optionalOffset = peOffset + 24;
  const magic = header.readUInt16LE(optionalOffset);
  const dataDirectoryOffset = optionalOffset + (magic === 0x20b ? 112 : 96);
  const securityOffset = dataDirectoryOffset + (4 * 8);
  const certificateFileOffset = header.readUInt32LE(securityOffset);
  const certificateSize = header.readUInt32LE(securityOffset + 4);
  if (!certificateFileOffset || !certificateSize) process.exit(0);

  const zeros = Buffer.alloc(8);
  await file.write(zeros, 0, zeros.length, securityOffset);
  const stat = await file.stat();
  if (certificateFileOffset + certificateSize === stat.size) {
    await file.truncate(certificateFileOffset);
  }
} finally {
  await file.close();
}

