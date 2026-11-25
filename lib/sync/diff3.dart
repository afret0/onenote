import 'dart:math' as math;

import 'package:diff_match_patch/diff_match_patch.dart' as dmp;

class Diff3Segment {
  const Diff3Segment.stable(this.text)
      : local = null,
        remote = null,
        isConflict = false;

  const Diff3Segment.conflict(String this.local, String this.remote)
      : text = null,
        isConflict = true;

  final bool isConflict;
  final String? text;
  final String? local;
  final String? remote;
}

class Diff3Result {
  Diff3Result(this.segments);

  final List<Diff3Segment> segments;

  bool get hasConflict => segments.any((s) => s.isConflict);

  int get conflictCount => segments.where((s) => s.isConflict).length;

  String mergedWith(List<bool> pickLocal) {
    final buffer = StringBuffer();
    var conflictIndex = 0;
    for (final segment in segments) {
      if (!segment.isConflict) {
        buffer.write(segment.text);
        continue;
      }
      final useLocal =
          conflictIndex < pickLocal.length ? pickLocal[conflictIndex] : true;
      buffer.write(useLocal ? segment.local : segment.remote);
      conflictIndex++;
    }
    return buffer.toString();
  }

  String get autoMerged => mergedWith(const []);
}

int _commonPrefix(String a, String b) {
  final max = math.min(a.length, b.length);
  var i = 0;
  while (i < max && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

int _commonSuffix(String a, String b, int skipPrefix) {
  final max = math.min(a.length, b.length) - skipPrefix;
  var i = 0;
  while (i < max &&
      a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
    i++;
  }
  return i;
}

class _TextEdit {
  _TextEdit(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

List<_TextEdit> _editsFromBase(String base, String other) {
  final diffs = dmp.diff(base, other);
  dmp.cleanupSemantic(diffs);
  final edits = <_TextEdit>[];
  var basePos = 0;
  for (final d in diffs) {
    switch (d.operation) {
      case dmp.DIFF_EQUAL:
        basePos += d.text.length;
      case dmp.DIFF_DELETE:
        if (edits.isNotEmpty && edits.last.end == basePos) {
          final last = edits.removeLast();
          edits.add(_TextEdit(last.start, basePos + d.text.length, last.text));
        } else {
          edits.add(_TextEdit(basePos, basePos + d.text.length, ''));
        }
        basePos += d.text.length;
      case dmp.DIFF_INSERT:
        if (edits.isNotEmpty && edits.last.end == basePos) {
          final last = edits.removeLast();
          edits.add(_TextEdit(last.start, last.end, last.text + d.text));
        } else {
          edits.add(_TextEdit(basePos, basePos, d.text));
        }
    }
  }
  return edits;
}

Diff3Result diff3Merge(String base, String local, String remote) {
  if (local == remote) {
    return Diff3Result([Diff3Segment.stable(local)]);
  }
  if (base == local) {
    return Diff3Result([Diff3Segment.stable(remote)]);
  }
  if (base == remote) {
    return Diff3Result([Diff3Segment.stable(local)]);
  }
  final localEdits = _editsFromBase(base, local);
  final remoteEdits = _editsFromBase(base, remote);
  final segments = <Diff3Segment>[];
  final stable = StringBuffer();
  var li = 0;
  var ri = 0;
  var basePos = 0;

  void flushStable(int until) {
    if (until > basePos) {
      stable.write(base.substring(basePos, until));
      basePos = until;
    }
    if (stable.isNotEmpty) {
      segments.add(Diff3Segment.stable(stable.toString()));
      stable.clear();
    }
  }

  void addConflict(String localText, String remoteText) {
    final prefix = _commonPrefix(localText, remoteText);
    final suffix = _commonSuffix(localText, remoteText, prefix);
    if (prefix > 0) {
      segments.add(Diff3Segment.stable(localText.substring(0, prefix)));
    }
    final localMid = localText.substring(prefix, localText.length - suffix);
    final remoteMid = remoteText.substring(prefix, remoteText.length - suffix);
    if (localMid.isNotEmpty || remoteMid.isNotEmpty) {
      segments.add(Diff3Segment.conflict(localMid, remoteMid));
    }
    if (suffix > 0) {
      segments.add(
          Diff3Segment.stable(localText.substring(localText.length - suffix)));
    }
  }

  while (li < localEdits.length || ri < remoteEdits.length) {
    if (li < localEdits.length && ri < remoteEdits.length) {
      final le = localEdits[li];
      final re = remoteEdits[ri];
      if (le.start == re.start && le.end == re.end && le.text == re.text) {
        flushStable(le.start);
        stable.write(le.text);
        basePos = le.end;
        li++;
        ri++;
        continue;
      }
    }
    final nextLocal =
        li < localEdits.length ? localEdits[li].start : base.length + 1;
    final nextRemote =
        ri < remoteEdits.length ? remoteEdits[ri].start : base.length + 1;
    int regionStart;
    int regionEnd;
    if (nextLocal <= nextRemote) {
      regionStart = localEdits[li].start;
      regionEnd = localEdits[li].end;
      li++;
    } else {
      regionStart = remoteEdits[ri].start;
      regionEnd = remoteEdits[ri].end;
      ri++;
    }
    var grew = true;
    while (grew) {
      grew = false;
      while (li < localEdits.length && localEdits[li].start <= regionEnd) {
        if (localEdits[li].end > regionEnd) {
          regionEnd = localEdits[li].end;
          grew = true;
        }
        li++;
      }
      while (ri < remoteEdits.length && remoteEdits[ri].start <= regionEnd) {
        if (remoteEdits[ri].end > regionEnd) {
          regionEnd = remoteEdits[ri].end;
          grew = true;
        }
        ri++;
      }
    }
    var localFirst = li;
    while (localFirst > 0 && localEdits[localFirst - 1].start >= regionStart) {
      localFirst--;
    }
    var remoteFirst = ri;
    while (remoteFirst > 0 &&
        remoteEdits[remoteFirst - 1].start >= regionStart) {
      remoteFirst--;
    }
    final localText = _applyEdits(
        base, regionStart, regionEnd, localEdits.sublist(localFirst, li));
    final remoteText = _applyEdits(
        base, regionStart, regionEnd, remoteEdits.sublist(remoteFirst, ri));
    final baseText = base.substring(regionStart, regionEnd);
    flushStable(regionStart);
    if (localText == remoteText || remoteText == baseText) {
      segments.add(Diff3Segment.stable(localText));
    } else if (localText == baseText) {
      segments.add(Diff3Segment.stable(remoteText));
    } else {
      addConflict(localText, remoteText);
    }
    basePos = regionEnd;
  }
  flushStable(base.length);
  if (segments.isEmpty) {
    segments.add(const Diff3Segment.stable(''));
  }
  return Diff3Result(segments);
}

String _applyEdits(String base, int start, int end, List<_TextEdit> edits) {
  final buffer = StringBuffer();
  var pos = start;
  for (final edit in edits) {
    if (edit.start > pos) {
      buffer.write(base.substring(pos, edit.start));
    }
    buffer.write(edit.text);
    pos = edit.end;
  }
  if (end > pos) {
    buffer.write(base.substring(pos, end));
  }
  return buffer.toString();
}