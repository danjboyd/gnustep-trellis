#!/usr/bin/env python3
# Generates Plan, Verify, Project and Plan-drawer .trellis from
# Intake.trellis (the shared shell) by swapping its marked regions
# (<!-- @rail -->, @header, @body, @actions, @reply, @note, @drawer,
# /* @extra-style */). Run from this directory: python3 -I gen-cards.py
import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
import re, sys
base = open('Intake.trellis').read()

def region(s, name, new):
    pat = re.compile(r'(<!-- @%s -->)(.*?)(\n?[ \t]*<!-- @/%s -->)' % (name, name), re.S)
    assert pat.search(s), name
    return pat.sub(lambda m: m.group(1) + new + m.group(3), s, count=1)

RAIL_DEFAULT = re.search(r'<!-- @rail -->(.*?)<!-- @/rail -->', base, re.S).group(1)

def rail_select(title):
    r = RAIL_DEFAULT.replace('<column class="row selected">', '<column class="row">')
    i = r.index('>' + title)
    j = r.rindex('<column class="row">', 0, i)
    return r[:j] + '<column class="row selected">' + r[j+len('<column class="row">'):]

def header(gate, meta, title, requester, heard, calm=True, tag=None):
    t = ('\n              <box class="hotfix-tag"><label class="hotfix-text">%s</label></box>' % tag) if tag else ''
    return '''
            <row class="gate-line">%s
              <label id="gateLine" class="gate">%s</label>
              <text class="meta">%s</text>
            </row>
            <text id="cardTitle" class="card-title">%s</text>
            <text id="requester" class="requester">%s</text>
            <row><box class="heard%s"><text id="lastHeard" class="heard-text">%s</text></box></row>''' % (
        t, gate, meta, title, requester, ' calm' if calm else '', heard)

def actions(primary_wide, primary_narrow, others, hint):
    out = '''
            <button class="wide-only" action="deskAction:" default="yes">%s</button>
            <button class="narrow-only" action="deskAction:" default="yes">%s</button>''' % (primary_wide, primary_narrow)
    for o in others:
        out += '\n            <button action="deskAction:">%s</button>' % o
    if hint:
        out += '\n            <text id="actionHint" class="hint">%s</text>' % hint
    return out

def reply(meta, body):
    return '''
          <text id="replyBody" class="reply-body">%s</text>''' % body, meta

def build(name, comment, rail, hdr, body, acts, rep, note, extra_style=''):
    s = base
    s = s.replace('''<!-- AIManager's Tickets triage desk (G3-G7), Intake gate: the proposal.
     From the approved mockup 1.''', comment, 1)
    s = region(s, 'rail', rail)
    s = region(s, 'header', hdr)
    s = region(s, 'body', body)
    s = region(s, 'actions', acts)
    rbody, rmeta = rep
    s = region(s, 'reply', rbody)
    s = re.sub(r'(<text id="replyMeta" class="reply-meta grow">)(.*?)(</text>)', lambda m: m.group(1) + rmeta + m.group(3), s, count=1)
    s = region(s, 'note', note)
    s = s.replace('  /* @extra-style */', '  /* @extra-style */' + extra_style, 1)
    open(name, 'w').write(s)

COMMON_STYLE = '''
  .hotfix-tag { background-color: #f6c08a; border-radius: 4px; padding: 1px 6px; }
  .expander  { flex-wrap: wrap; gap: 4px 12px; align-items: center; padding: 6px 0; }
  .exp-note  { flex: 0 1 auto; min-width: 0; text-align: right; }
  .tint      { background-color: Mark; border-radius: 6px; }
  .tint text, .tint label { color: MarkText; }'''

# ---------------- Plan ----------------
build('Plan.trellis',
'''<!-- AIManager's Tickets triage desk (G3-G7), Plan gate on a hotfix: the
     proposal. From the approved mockup 2 (the drawer is closed here; see
     Plan-drawer.trellis for the agent chat).''',
rail_select('Login page returns 500'),
header('PLAN: IS THIS THE RIGHT FIX?', '#491 · Sign-in · Opened 31 min ago · agent-web',
       'Login page returns 500 after password reset', 'Sam Ortiz, Operations · Unblocks 1 ticket',
       'Requester last heard from us: 19 min ago, acknowledgment', tag='Hotfix'),
'''
          <column id="cardBody" class="card-body">
            <column class="block">
              <label class="sec">Diagnosis · confidence high</label>
              <text class="lead">After a password reset, the sign-in handler looks up the old reset token, finds it deleted, and throws instead of continuing. Anyone who resets a password cannot sign in until their session cookie is cleared.</text>
              <text class="small">Based on: reproduced on staging; the stack trace ends in the reset-token lookup</text>
            </column>
            <column class="block">
              <label class="sec">Proposed fix</label>
              <column id="steps" class="steps">
                <text>1. Treat a missing reset token as already used, and continue sign-in.</text>
                <text>2. Add a test that signs in immediately after a reset.</text>
                <text>3. Deploy to production and watch the sign-in error rate.</text>
              </column>
            </column>
            <column class="block blast">
              <label class="sec">Blast radius</label>
              <box class="blast-grid">
                <column class="cell"><text class="cell-head">Affects</text><text>Sign-in service, every user signing in</text></column>
                <column class="cell"><text class="cell-head">Reversible</text><text>Yes, by redeploying the previous build</text></column>
                <column class="cell"><text class="cell-head">Goes live immediately</text><text>Yes, on deploy</text></column>
              </box>
            </column>
            <column class="block">
              <separator/>
              <row class="expander"><button action="expandSection:">▸ Alternatives considered</button><spacer/><text class="small exp-note">2 · Space to expand</text></row>
              <separator/>
              <row class="expander"><button action="expandSection:">▸ Evidence</button><spacer/><text class="small exp-note">4 items</text></row>
              <separator/>
            </column>
          </column>''',
actions('Approve and send diagnosis update · Return', 'Approve and send · Return',
        ['Revise · R', 'Reassign · G', 'Take over · O', 'Decline · X'],
        'Shift+Return approves without sending'),
reply('Reply to Sam Ortiz · Draft: diagnosis update · updated after chat · visible to requester',
      'Hi Sam, we have found the cause. Signing in right after a password reset hits an error on our side. A fix is ready and we are deploying it now. In the meantime, clearing your browser cookies for the site will let you sign in.'),
'<field id="note" placeholder="Note to agent-web (N), optional"/>',
COMMON_STYLE + '''
  .steps     { gap: 4px; }
  .blast     { padding: 12px 16px; border-radius: 6px; background-color: -tr-window-background; }
  .cell-head { font-weight: bold; }
  .blast-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px; }
  @container (max-width: 639px) { .blast-grid { grid-template-columns: minmax(0, 1fr); } }''')

# ---------------- Verify ----------------
build('Verify.trellis',
'''<!-- AIManager's Tickets triage desk (G3-G7), Verify gate: the proposal.
     From the approved mockup 3 (the drawer is closed; the undo bar shows a
     held approval from the previous card).''',
rail_select('Dashboard chart shows'),
header('VERIFY: DID IT WORK?', '#467 · Standard · Dashboards · Opened 2 days ago · agent-web',
       'Dashboard chart shows the wrong fiscal quarter', 'Dana Whitfield, Finance',
       'Requester last heard from us: yesterday, diagnosis update'),
'''
          <column id="cardBody" class="card-body">
            <column class="block">
              <label class="sec">What was done, against the approved plan</label>
              <column id="steps" class="steps">
                <row class="step"><label class="step-state">Done</label><text class="grow">Read the fiscal year start from settings instead of assuming January.</text></row>
                <row class="step"><label class="step-state">Done</label><text class="grow">Add tests for fiscal years that start mid-year.</text></row>
                <row class="step tint"><label class="step-state">Changed</label><text class="grow">Plan said to fix the quarterly chart only. The same assumption was in the year-to-date tile, so that was fixed too.</text></row>
              </column>
            </column>
            <box class="proof">
              <column class="block">
                <label class="sec">Proof · verified by agent</label>
                <text>New and existing chart tests pass. Before and after screenshots of the dashboard attached.</text>
              </column>
              <column class="block">
                <label class="sec">Live status</label>
                <text class="live">Deployed and live</text>
              </column>
            </box>
            <column class="block">
              <separator/>
              <row class="expander"><button action="expandSection:">▸ Change detail</button><spacer/><text class="small exp-note">1 commit, 3 files · Space to expand</text></row>
              <separator/>
            </column>
          </column>''',
actions('Confirm, close and send fix confirmation · Return', 'Confirm and close · Return',
        ['Reopen · R', 'Take over · O'], None),
reply('Reply to Dana Whitfield · Draft: fix confirmation · visible to requester',
      'Hi Dana, this is fixed and live now. The dashboard chart and the year-to-date tile both follow your fiscal year settings. Please refresh the page, and reply here if anything still looks off.'),
'<field id="note" placeholder="Note (N), optional"/>',
COMMON_STYLE + '''
  .steps     { gap: 2px; }
  .step      { gap: 12px; padding: 8px 12px; align-items: baseline; }
  .step-state { flex: none; width: 76px; font-weight: bold; }
  .proof     { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
  .live      { font-size: 15px; font-weight: bold; }
  .undo      { display: flex; }
  @container (max-width: 639px) {
    .proof   { grid-template-columns: minmax(0, 1fr); }
    .step    { flex-wrap: wrap; row-gap: 2px; }
    .step .grow { flex: 1 1 200px; }
  }''')
# Verify's undo text
s = open('Verify.trellis').read()
s = s.replace('<text id="undoLabel" class="grow undo-text">Nothing to undo</text>',
              '<text id="undoLabel" class="grow undo-text">Approved #491 and queued the diagnosis update to Sam Ortiz. Leaves in 7 s.</text>')
open('Verify.trellis', 'w').write(s)

# ---------------- Project ----------------
PROJECT_RAIL = '''
          <row class="folded"><label class="section grow">Your move</label><label>4</label></row>
          <column class="row"><text class="row-title">Rebuild the receivables report on the warehouse</text><text class="row-meta">Plan · Reports migration · agent-data · 25 min</text></column>
          <label class="more">and 3 more</label>
          <separator class="rail-sep"/>
          <row class="folded"><label class="grow">With agents</label><label>7</label></row>
          <row class="folded"><label class="grow">With requesters</label><label>2</label></row>
          <row class="folded"><label class="grow">Blocked</label><label>2</label></row>
          <column class="row"><text class="row-title">Retire the old nightly export job</text><text class="row-meta">Waiting on #503 and #504</text></column>
          <column class="row"><text class="row-title">Point dashboards at the warehouse</text><text class="row-meta">Waiting on #503</text></column>
          <row class="folded"><label class="grow">Projects</label><label>1</label></row>
          <column class="row selected"><text class="row-title">Reports migration</text><text class="row-meta">3 of 7 done · 1 needs you · 2 blocked</text></column>
          <row class="folded"><label class="grow">Snoozed</label><label>0</label></row>'''

def wi(state, item, agent, dep, cls=''):
    return '''
                <box class="wi%s"><text class="wi-st">%s</text><text class="wi-it">%s</text><text class="wi-ag">%s</text><text class="wi-dp">%s</text></box>''' % (
        (' ' + cls) if cls else '', state, item, agent, dep)

build('Project.trellis',
'''<!-- AIManager's Tickets triage desk (G3-G7), a Project with work items
     and prerequisites: the proposal. From the approved mockup 4.''',
PROJECT_RAIL,
header('PROJECT', '#498 · Reports · Opened 9 days ago',
       'Move all reports to the new data warehouse', 'Maria Lopez, Accounting',
       'Requester last heard from us: 4 days ago, progress update'),
'''
          <column id="cardBody" class="card-body">
            <column class="block">
              <row class="progress-head"><label class="strong">3 of 7 work items done</label><text class="small grow progress-note">1 needs you · 1 with an agent · 2 blocked</text></row>
              <box id="progress" class="segments">
                <box class="seg done"/><box class="seg done"/><box class="seg done"/>
                <box class="seg needs"/><box class="seg fixing"/><box class="seg open"/><box class="seg open"/>
              </box>
            </column>
            <column id="workItems" class="table">
              <box class="wi wi-head"><label class="wi-st sec">State</label><label class="wi-it sec">Work item</label><label class="wi-ag sec">Agent</label><label class="wi-dp sec">Depends on</label></box>'''
 + wi('Done', '#499 Inventory every report and its data source', 'agent-data', 'None', 'quiet')
 + wi('Done', '#500 Load ledger tables into the warehouse', 'agent-infra', '#499', 'quiet')
 + wi('Done', '#501 Rebuild the trial balance report', 'agent-data', '#500', 'quiet')
 + wi('Needs you', '#502 Rebuild the receivables report · Plan gate', 'agent-data', '#500', 'mine')
 + wi('Fixing', '#503 Rebuild the payables report', 'agent-data', '#500')
 + wi('Blocked', '#505 Point dashboards at the warehouse', 'agent-web', '#503')
 + wi('Blocked', '#506 Retire the old nightly export job', 'agent-infra', '#503, #504 vendor sign-off') + '''
            </column>
          </column>''',
actions('Open #502 at its Plan gate · Return', 'Open #502 · Return',
        ['Add work item', 'Add prerequisite · B'], 'The project gets one Verify gate when all items close'),
reply('Reply to Maria Lopez · Draft: progress update · visible to requester',
      'Hi Maria, a quick update on the reports move. The trial balance report is now running on the new warehouse, and receivables and payables are in progress. Dashboards and retiring the old export come after those. We will write again when receivables is live.'),
'<field id="note" placeholder="Note (N), optional"/>',
COMMON_STYLE + '''
  .strong    { font-weight: bold; }
  .more      { color: GrayText; font-size: 12px; padding: 0 8px; }
  .progress-head { flex-wrap: wrap; gap: 4px 12px; align-items: baseline; }
  .progress-note { text-align: right; }
  .segments  { display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 4px; }
  .seg       { height: 8px; border-radius: 2px; }
  .done      { background-color: CanvasText; }
  .needs     { background-color: AccentColor; }
  .fixing    { background-color: GrayText; }
  .open      { background-color: -tr-separator; }
  .table     { gap: 0; }
  .wi        { display: grid; grid-template-columns: 96px minmax(0, 1fr) 110px 150px;
               grid-template-areas: "st it ag dp"; gap: 4px 12px; padding: 9px 8px;
               align-items: start; }
  .wi-st     { grid-area: st; }
  .wi-it     { grid-area: it; }
  .wi-ag     { grid-area: ag; }
  .wi-dp     { grid-area: dp; }
  .quiet text, .quiet label { color: GrayText; }
  .mine      { background-color: Highlight; border-radius: 6px; }
  .mine text, .mine label { color: HighlightText; font-weight: bold; }
  @container (max-width: 759px) {
    .wi      { grid-template-columns: 84px minmax(0, 1fr) minmax(0, 1fr);
               grid-template-areas: "st it it" ". ag dp"; }
    .wi-head .wi-ag, .wi-head .wi-dp { display: none; }
    .progress-note { text-align: left; }
  }''')
print("ok")

# ---------------- Plan with the drawer open (agent chat) ----------------
s = open('Plan.trellis').read()
s = s.replace('''<!-- AIManager's Tickets triage desk (G3-G7), Plan gate on a hotfix: the
     proposal. From the approved mockup 2 (the drawer is closed here; see
     Plan-drawer.trellis for the agent chat).''', '''<!-- AIManager's Tickets triage desk (G3-G7), Plan gate with the drawer
     open on Agent chat: the proposal. From the approved mockup 2.
     - From 1100px up the drawer is a 360px column beside the card.
     - Below 1100px it takes the card column's place (the card is one
       Escape away), so neither is squeezed.''', 1)
def msg(who, when, text):
    return '''
          <column class="msg"><label class="small">%s · %s</label><text>%s</text></column>''' % (who, when, text)
drawer = '''
      <row class="tabs">
        <!-- The drawer's tabs: a pop-up until Trellis has a segmented control. -->
        <popup id="drawerTabs" action="drawerTab:" a11y-label="Drawer tab" items="Agent chat, Ticket, Timeline, Requester, Related, Trust"/>
        <spacer/>
        <button action="closeDrawer:" a11y-label="Close the drawer">× Esc</button>
      </row>
      <separator/>
      <scroll class="drawer-scroll">
        <column class="drawer-body">
          <row class="chat-head"><text class="small grow">Internal · agent-web on #491 · never shown to the requester</text><button action="drawerTab:">Show raw transcript</button></row>''' \
  + msg('You', '3 min ago', 'Why not just restart the sign-in service? Would that clear it?') \
  + msg('agent-web', '3 min ago', 'No. The error is in the code path, not in cached state, so it would come back on the next password reset. A restart would only sign everyone out.') \
  + msg('You', '1 min ago', 'Fine. Mention the cookie workaround in the reply to Sam.') \
  + msg('agent-web', '1 min ago', 'Done. I added one sentence about clearing cookies to the draft. The plan itself is unchanged.') + '''
          <row><box class="revised"><text class="revised-text">Revised brief: draft changed · plan unchanged</text></box></row>
        </column>
      </scroll>
      <column class="composer">
        <field id="chatInput" placeholder="Ask agent-web about this ticket"/>
        <row class="actions-plain">
          <button action="sendToAgent:" default="yes">Send to agent · Return</button>
          <button action="sendAsRevision:">Send as revision</button>
        </row>
        <text class="small">Chat does not approve anything. C opens this pane; Escape returns to the card.</text>
      </column>
    '''
assert '<!-- @drawer -->' in s
s = s.replace('<!-- @drawer -->', '<!-- @drawer -->' + drawer, 1)
# The card's own primary loses Return while the chat field has focus; keep
# one default button in the drawer variant.
s = s.replace('<button class="wide-only" action="deskAction:" default="yes">', '<button class="wide-only" action="deskAction:">')
s = s.replace('<button class="narrow-only" action="deskAction:" default="yes">', '<button class="narrow-only" action="deskAction:">')
s = s.replace('  /* @extra-style */', '''  /* @extra-style */
  .drawer    { display: flex; flex: none; width: 360px; border-color: -tr-separator;
               background-color: Canvas; }
  .tabs      { flex-wrap: wrap; gap: 4px; padding: 8px 10px; align-items: center; }
  .drawer-scroll { flex: 1; min-height: 0; }
  .drawer-body { gap: 12px; padding: 12px 16px; }
  .chat-head { flex-wrap: wrap; gap: 6px 10px; align-items: center; }
  .chat-head .grow { flex: 1 1 100%; }
  .msg       { gap: 2px; }
  .revised   { background-color: Highlight; border-radius: 4px; padding: 3px 8px; }
  .revised-text { color: HighlightText; font-size: 12px; }
  .composer  { gap: 6px; padding: 10px 16px 12px 16px; }
  .actions-plain { flex-wrap: wrap; gap: 8px; }
  /* Below 1100px the drawer takes the card column's place. */
  @container (max-width: 1099px) {
    .main    { display: none; }
    .drawer  { flex: 1; width: auto; min-width: 0; }
  }''', 1)
open('Plan-drawer.trellis', 'w').write(s)
print("drawer ok")
