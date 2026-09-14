'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { loadArchive, validateArchive } = require('../scripts/validate-ftp-evidence');

// Each negative case starts with a passing archive and changes one fact only;
// no packet, metadata or TSV file is written by these tests.
function rejectsMutation(change, message) {
  const archive = loadArchive();
  validateArchive(archive);
  change(archive);
  assert.throws(() => validateArchive(archive), message);
}

test('checked-in FTP archive agrees with reviewed capture/session boundaries', () => {
  assert.deepEqual(validateArchive(loadArchive()), { primaryFrames: 71, supplementalFrames: 36 });
});

test('CRLF and LF checkouts preserve the same TSV evidence', () => {
  for (const newline of ['\n', '\r\n']) {
    const archive = loadArchive();
    for (const capture of Object.values(archive.captures)) {
      capture.tsv = capture.tsv.replace(/\r\n/g, '\n').replace(/\n/g, newline);
    }
    assert.equal(validateArchive(archive).primaryFrames, 71);
  }
});

test('old total and silently including the active supplement are rejected', () => {
  for (const frames of [74, 107]) {
    rejectsMutation(a => { a.metadata.result.frames = frames; }, /result.frames/);
  }
});

test('primary capture scope cannot silently include the separate active file', () => {
  rejectsMutation(a => {
    a.metadata.result.capture = 'captures/real-app-netns/{telnet,ftp,ftp-active}.pcapng';
  }, /result.capture/);
});

test('old 40-frame passive count and shifted session boundaries are rejected', () => {
  rejectsMutation(a => { a.metadata.result.ftp.passive_frames = 40; }, /ftp.passive_frames/);
  rejectsMutation(a => { a.metadata.result.ftp.login_only_frame_range = [41, 64]; }, /ftp.login_only_frame_range/);
});

test('login-only session cannot be relabeled as an active transfer', () => {
  rejectsMutation(a => { a.metadata.result.ftp.active_frames = 22; }, /mislabeled login-only session/);
  rejectsMutation(a => {
    a.metadata.result.ftp.active_data_connection = '198.18.0.2:20 -> 198.18.0.1:<ephemeral>';
  }, /mislabeled login-only session/);
});

test('active data connection pins observed source port and SYN direction', () => {
  for (const connection of [
    '198.18.0.2:20 -> 198.18.0.1:47135',
    '198.18.0.1:47135 -> 198.18.0.2:48707',
  ]) {
    rejectsMutation(a => { a.metadata.result.ftp_active_supplement.data_connection = connection; }, /ftp_active_supplement.data_connection/);
  }
});

test('separate active capture cannot borrow the original control port or transcript', () => {
  rejectsMutation(a => {
    a.metadata.result.ftp_active_supplement.control_connection = '198.18.0.1:33594 -> 198.18.0.2:2121';
  }, /ftp_active_supplement.control_connection/);
  rejectsMutation(a => {
    a.metadata.result.ftp_active_supplement.transcript = 'captures/real-app-netns/ftp-active.log';
  }, /ftp_active_supplement.transcript/);
});

test('changing a pcap byte needs renewed packet review', () => {
  rejectsMutation(a => { a.captures['ftp-active'].pcap[100] ^= 1; }, /ftp-active: reviewed pcap SHA-256/);
});

test('TSV edits and truncation cannot retain the old packet review', () => {
  rejectsMutation(a => {
    a.captures['ftp-active'].tsv = a.captures['ftp-active'].tsv.replace('48707', '20');
  }, /ftp-active: reviewed TSV SHA-256/);
  rejectsMutation(a => {
    a.captures.ftp.tsv = a.captures.ftp.tsv.replace(/64\t[^\n]*\n$/, '');
  }, /ftp: reviewed TSV SHA-256/);
});
