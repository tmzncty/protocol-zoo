'use strict';

// Fixed, reviewed archive contract, NOT a pcap decoder or a live FTP experiment.
// See species/ftp/capture-reading.md. Replacing captures requires a new packet
// review; updating these hashes alone does not establish equivalent evidence.
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');
const DIRECTORY = 'captures/real-app-netns/';
const CAPTURES = {
  telnet: {
    frames: 7,
    pcap: 'c1ca5a1c68162a23148f7169e7013bc2c79245ff0a54601197d5a8d2274d02ea',
    tsv: 'c22efc72dbf1fc78e6330d568e46d1cb14d0d03f50422fb0445cc949bfbbe43d',
  },
  ftp: {
    frames: 64,
    pcap: 'c8e20e2c1cd7c5cb2a364af2be410d08893d14942d18712c6922f37b6aab1167',
    tsv: '19abf0a727daa3f9a1c0352e5bd6f6af4ae1203b925cf56e19529a18d3d14ccb',
  },
  'ftp-active': {
    frames: 36,
    pcap: 'c4c3605050be68815cac3951bd471f499cba1767fb1f2d7fe2ad9f056ca00cc3',
    tsv: 'a3b7363f0c20c933b0e1dbc469febe6397b16cc068befa63ba98c5604de44464',
  },
};

function loadArchive(root = ROOT) {
  const read = name => fs.readFileSync(path.join(root, DIRECTORY, name));
  return {
    metadata: JSON.parse(read('real-app.json').toString('utf8')),
    captures: Object.fromEntries(Object.keys(CAPTURES).map(name => [name, {
      pcap: read(`${name}.pcapng`),
      tsv: read(`${name}.frames.tsv`).toString('utf8'),
    }])),
  };
}

function validateArchive(archive) {
  const hash = data => createHash('sha256').update(data).digest('hex');
  for (const [name, expected] of Object.entries(CAPTURES)) {
    const capture = archive.captures[name];
    assert.ok(capture, `missing archive: ${name}`);
    assert.equal(hash(capture.pcap), expected.pcap, `${name}: reviewed pcap SHA-256`);
    // Git checkouts may use CRLF. Do not trim fields, blank rows or whitespace.
    const tsv = capture.tsv.replace(/\r\n/g, '\n');
    assert.equal(hash(tsv), expected.tsv, `${name}: reviewed TSV SHA-256`);
    const lines = tsv.split('\n');
    assert.equal(lines.pop(), '', `${name}: final newline`);
    const header = lines.shift().split('\t');
    assert.equal(header[0], 'frame.number');
    assert.equal(lines.length, expected.frames, `${name}: TSV frame count`);
    lines.forEach((line, index) => {
      const fields = line.split('\t');
      assert.equal(fields.length, header.length, `${name}: columns at frame ${index + 1}`);
      assert.equal(fields[0], String(index + 1), `${name}: consecutive frame numbers`);
    });
  }

  const result = archive.metadata.result;
  assert.ok(result, 'missing experiment result');
  function fields(actual, expected, label) {
    assert.ok(actual && typeof actual === 'object', `${label}: missing object`);
    for (const [key, value] of Object.entries(expected)) {
      assert.deepEqual(actual[key], value, `${label}.${key}`);
    }
  }
  fields(result, {
    capture: `${DIRECTORY}{telnet,ftp}.pcapng`,
    frames: CAPTURES.telnet.frames + CAPTURES.ftp.frames,
  }, 'result');
  fields(result.telnet, { frames: CAPTURES.telnet.frames, negotiation_frame: 6 }, 'telnet');
  fields(result.ftp, {
    capture: `${DIRECTORY}ftp.pcapng`,
    frames: CAPTURES.ftp.frames,
    control_connections: 2,
    passive_control_connection: '198.18.0.1:40734 -> 198.18.0.2:2121',
    passive_data_connection: '198.18.0.1:40810 -> 198.18.0.2:19000',
    passive_frame_range: [1, 42],
    passive_frames: 42,
    passive_transcript: `${DIRECTORY}ftp-passive.log`,
    retrieved_bytes: 25,
    login_only_control_connection: '198.18.0.1:40750 -> 198.18.0.2:2121',
    login_only_frame_range: [43, 64],
    login_only_frames: 22,
    login_only_transcript: `${DIRECTORY}ftp-active.log`,
  }, 'ftp');
  for (const obsolete of ['active_data_connection', 'active_frames']) {
    assert.ok(!Object.hasOwn(result.ftp, obsolete), `ftp.${obsolete}: mislabeled login-only session`);
  }
  fields(result.ftp_active_supplement, {
    capture: `${DIRECTORY}ftp-active.pcapng`,
    frames: CAPTURES['ftp-active'].frames,
    control_connections: 1,
    control_connection: '198.18.0.1:33594 -> 198.18.0.2:2122',
    data_connection: '198.18.0.2:48707 -> 198.18.0.1:47135',
    eprt_frame: 18,
    data_syn_frame: 19,
    list_frame: 23,
    transfer_complete_frame: 30,
    transcript: null,
  }, 'ftp_active_supplement');
  assert.equal(result.ftp.passive_frames + result.ftp.login_only_frames, result.ftp.frames);
  return { primaryFrames: result.frames, supplementalFrames: result.ftp_active_supplement.frames };
}

if (require.main === module) {
  try {
    const result = validateArchive(loadArchive());
    console.log(`FTP archive consistency: pass (${result.primaryFrames} primary + ${result.supplementalFrames} supplemental frames; no live experiment)`);
  } catch (error) {
    console.error(`FTP archive consistency: ${error.message}`);
    process.exitCode = 1;
  }
}

module.exports = { loadArchive, validateArchive };
