/**
 ERS_LAN_Fixed.pde
 Egyptian Rat Screw — LAN multiplayer (host/client)
 Processing 4.3 single-file sketch — fixed and complete.

 - Run on two machines.
 - One machine: choose "Host" and Start Host.
 - Other machine: choose "Client", click the IP box, type host IP, press Enter or Connect.
 - Host is authoritative.
 - Controls:
    Host (Player 1): Flip A, Slap S
    Client (Player 2): Flip L, Slap K
 - Space = pause (client/host local), R = restart (host only)
*/

import processing.net.*;
import java.util.*;

// ---- network config ----
int NET_PORT = 5204;
Server netServer = null;
Client netClient = null;
boolean isHost = false;
boolean isClient = false;
String hostIP = "";
int clientID = -1; // client connection id (host only)

// ---- game constants ----
final int CARD_W = 70;
final int CARD_H = 100;
final int MAX_SHOW_PILE = 8;

// ---- game state (host authoritative) ----
ArrayList<Card> deck = new ArrayList<Card>();
ArrayList<Card> pile = new ArrayList<Card>();
ArrayList<Card> p1 = new ArrayList<Card>();
ArrayList<Card> p2 = new ArrayList<Card>();

boolean p1Turn = true;
boolean paused = false;
boolean gameOver = false;

// local copies for client rendering (keeps UI responsive)
ArrayList<Card> localPile = new ArrayList<Card>();
ArrayList<Card> localP1 = new ArrayList<Card>();
ArrayList<Card> localP2 = new ArrayList<Card>();
boolean localP1Turn = true;
boolean localGameOver = false;
String localMsg = "Not connected.";

// ---- animation manager (keeps visuals) ----
AnimationManager anim;
FadingText resultText;

// ---- UI connection panel ----
String mode = "Idle"; // "Idle", "Host", "Client"
String inputIP = "";
String connectionStatus = "Not connected";

// typing state for IP box (click-to-type)
boolean typingIP = false;
int ipBoxX = 20, ipBoxY = 218, ipBoxW = 140, ipBoxH = 22;
int blinkFrame = 0;

// ---- CPU option for single-machine testing ----
boolean cpuModeLocal = false;
int cpuReaction = 25;
int cpuWait = 0;

// ---------- setup ----------
void settings() {
  size(1000, 620);
}
void setup() {
  textFont(createFont("Arial", 14));
  anim = new AnimationManager();
  resultText = new FadingText();
  resetLocalState();
  initHostState(); // create deck but only host will use it
  mode = "Idle";
  localMsg = "Choose Host or Client";
}

// ---------- host init ----------
void initHostState() {
  deck.clear(); pile.clear(); p1.clear(); p2.clear();
  String[] suits = {"\u2660","\u2665","\u2666","\u2663"};
  String[] ranks = {"A","2","3","4","5","6","7","8","9","10","J","Q","K"};
  for (String s : suits) for (int i=0;i<ranks.length;i++) deck.add(new Card(ranks[i], s, i+1));
  Collections.shuffle(deck, new Random());
  for (int i=0; i<deck.size(); i++) {
    if (i%2==0) p1.add(deck.get(i));
    else p2.add(deck.get(i));
  }
  deck.clear();
  p1Turn = true;
  gameOver = false;
  paused = false;
  // update local copies for immediate UI
  copyToLocal();
}

// ---------- reset client local arrays ----------
void resetLocalState() {
  localPile.clear(); localP1.clear(); localP2.clear();
  localP1Turn = true; localGameOver = false;
  inputIP = "";
  typingIP = false;
}

// ---------- draw ----------
void draw() {
  background(30, 120, 40);

  // left UI: connection panel / info
  drawConnectionPanel();

  // center: table
  pushMatrix();
  translate(200, 80);
  drawTableArea();
  popMatrix();

  // right: network status & instructions
  drawRightPanel();

  // update animations and draw overlays
  anim.update();
  anim.drawOverlays();
  resultText.updateAndDraw();

  // if client: try to read network messages
  if (isClient && netClient != null && netClient.available() > 0) {
    String s = netClient.readStringUntil('\n');
    if (s != null) handleNetMessageFromHost(s.trim());
  }

  // if host: accept new clients & process commands
  if (isHost && netServer != null) {
    Client c = netServer.available();
    while (c != null) {
      // check for data from existing client sockets
      if (c.available() > 0) {
        String msg = c.readStringUntil('\n');
        if (msg != null) {
          handleNetMessageFromClient(c, msg.trim());
        }
      }
      c = netServer.available();
    }
  }

  // CPU for testing when running single-machine host
  if (isHost && cpuModeLocal && !anim.isBusy()) handleCPUHost();

  // blinking cursor timer
  blinkFrame = (blinkFrame + 1) % 60;
}

// ---------- connection panel ----------
void drawConnectionPanel() {
  fill(20, 20, 30, 200);
  rect(10, 10, 180, height-20, 8);
  fill(255);
  textAlign(LEFT, TOP);
  textSize(14);
  text("LAN ERS - Connection", 20, 18);
  textSize(12);
  text("Mode: " + mode, 20, 46);
  text("Status: " + connectionStatus, 20, 66);
  text("Local message:", 20, 92);
  text(localMsg, 20, 110);

  // host button
  if (mode.equals("Idle") || mode.equals("Client")) {
    if (drawButton("Start Host", 20, 150, 140, 28)) {
      startHost();
    }
  } else {
    if (drawButton("Stop Host", 20, 150, 140, 28)) {
      stopHost();
    }
  }

  // client UI
  text("Connect to host IP:", 20, 198);

  // draw the interactive text box
  if (typingIP) stroke(255, 255, 120); else stroke(120);
  fill(255);
  rect(ipBoxX, ipBoxY, ipBoxW, ipBoxH, 4);
  noStroke();
  fill(0);
  textAlign(LEFT, CENTER);
  textSize(12);
  String showText = inputIP;
  if (typingIP && (blinkFrame < 30)) {
    // show blinking caret
    showText = inputIP + "|";
  }
  text(showText, ipBoxX + 6, ipBoxY + ipBoxH/2);

  if (!isClient) {
    if (drawButton("Connect", 20, 250, 66, 26)) {
      startClient(inputIP);
    }
  } else {
    if (drawButton("Disconnect", 20, 250, 66, 26)) {
      stopClient();
    }
  }

  // small controls
  fill(255);
  textSize(12);
  text("Controls (Host=Player1, Client=Player2):", 20, 294);
  text("Host Flip A   Slap S   R restart", 20, 314);
  text("Client Flip L  Slap K", 20, 334);

  // CPU toggle for testing
  if (drawButton(cpuModeLocal ? "CPU: ON" : "CPU: OFF", 20, 370, 140, 26)) {
    cpuModeLocal = !cpuModeLocal;
  }

  // port info
  text("Port: " + NET_PORT, 20, 410);
  text("Local IP: " + getLocalIP(), 20, 432);
}

// simple button: draws and returns true if clicked
boolean drawButton(String label, int x, int y, int w, int h) {
  boolean clicked = false;
  int mx = mouseX, my = mouseY;
  boolean hover = mx >= x && mx <= x+w && my >= y && my <= y+h;
  if (hover) fill(255, 220);
  else fill(200);
  rect(x, y, w, h, 6);
  fill(0);
  textAlign(CENTER, CENTER);
  text(label, x + w/2, y + h/2);
  if (hover && mousePressed) {
    clicked = true;
    // small delay to avoid multiple triggers
    delay(120);
  }
  return clicked;
}

// ---------- right panel ----------
void drawRightPanel() {
  fill(20, 20, 30, 200);
  rect(width-210, 10, 200, height-20, 8);
  fill(255);
  textAlign(LEFT, TOP);
  textSize(14);
  text("Network Log", width-200, 18);
  textSize(12);
  text("Mode: " + mode, width-200, 46);
  text("Conn: " + (isHost ? "Host" : (isClient ? "Client" : "None")), width-200, 66);
  text("ClientID: " + clientID, width-200, 90);
}

// ---------- table rendering ----------
void drawTableArea() {
  // background table
  fill(40, 120, 40);
  rect(0, 0, width-420, height-160, 8);

  // player1 area (left)
  pushMatrix();
  translate(40, 80);
  drawPlayerArea(localP1, "Player 1", localP1Turn);
  popMatrix();

  // player2 area (right)
  pushMatrix();
  translate(width-420-40 - CARD_W, 80);
  drawPlayerArea(localP2, "Player 2", !localP1Turn);
  popMatrix();

  // central pile
  pushMatrix();
  translate((width-420)/2 - CARD_W/2, (height-160)/2 - CARD_H/2);
  PVector shake = anim.getPileShakeOffset();
  translate(shake.x, shake.y);
  drawPileLocal();
  popMatrix();
}

void drawPlayerArea(ArrayList<Card> deckList, String name, boolean active) {
  noStroke();
  fill(0, 120);
  rect(-30, -120, CARD_W + 60, 40, 8);
  fill(255);
  textAlign(CENTER, CENTER);
  text(name + " (" + deckList.size() + ")", CARD_W/2, -100);

  pushMatrix();
  translate(0, -20);
  if (deckList.size() > 0) {
    for (int i=0; i<min(deckList.size(), 6); i++) {
      pushMatrix();
      translate(-i*2, i*2);
      drawCardBack();
      popMatrix();
    }
  } else {
    fill(255, 220);
    rect(0, 0, CARD_W, CARD_H, 6);
    fill(0);
    textAlign(CENTER, CENTER);
    text("Empty", CARD_W/2, CARD_H/2);
  }
  popMatrix();

  if (active) {
    noFill();
    stroke(255, 255, 0);
    strokeWeight(3);
    rect(-10, -30, CARD_W+20, CARD_H+40, 8);
    noStroke();
  }
}

void drawPileLocal() {
  fill(0, 0, 0, 30);
  rect(-10, -10, CARD_W+20, CARD_H+20, 6);
  if (localPile.size() == 0) {
    fill(255);
    rect(0, 0, CARD_W, CARD_H, 6);
    fill(0);
    textAlign(CENTER, CENTER);
    text("Pile", CARD_W/2, CARD_H/2);
    return;
  }
  int show = min(localPile.size(), MAX_SHOW_PILE);
  for (int i=0; i<show; i++) {
    Card c = localPile.get(localPile.size()-show + i);
    pushMatrix();
    translate(i*3, -i*2);
    if (!(anim.isCardBeingFlipped() && i == show-1 && anim.flipPendingTopEquals(c))) {
      c.drawFace(0, 0, CARD_W, CARD_H);
    }
    popMatrix();
  }
}

void drawCardBack() {
  fill(20, 20, 100);
  rect(0, 0, CARD_W, CARD_H, 6);
  fill(255);
  textAlign(CENTER, CENTER);
  text("Card", CARD_W/2, CARD_H/2 - 10);
  textSize(12);
  text("Back", CARD_W/2, CARD_H/2 + 10);
  textSize(14);
}

// ---------- input handling ----------
void keyPressed() {
  // If the IP box is focused, handle typing first
  if (typingIP) {
    handleIPTyping(key, keyCode);
    return;
  }

  if (key == 'r' || key == 'R') {
    if (isHost) {
      initHostState();
      sendStateToAll();
    }
    return;
  }
  if (key == ' ') {
    paused = !paused;
    return;
  }

  // local host controls (authoritative)
  if (isHost) {
    if (anim.isBusy()) return;
    if ((key == 'A' || key == 'a')) {
      hostHandleFlip(1);
    } else if ((key == 'S' || key == 's')) {
      hostHandleSlap(1);
    }
  }

  // client sends actions to host
  if (isClient) {
    if ((key == 'L' || key == 'l')) {
      sendClientAction("FLIP");
    } else if ((key == 'K' || key == 'k')) {
      sendClientAction("SLAP");
    }
  }
}

// IP typing handler (click to focus, digits/dot/backspace/enter)
void handleIPTyping(char k, int kcode) {
  if (kcode == BACKSPACE) {
    if (inputIP.length() > 0) inputIP = inputIP.substring(0, inputIP.length()-1);
    return;
  }
  if (kcode == ENTER || kcode == RETURN) {
    // attempt to connect
    startClient(inputIP.trim());
    typingIP = false;
    return;
  }
  // allow numbers, dots, and colon (port) and digits and letters for IPv6 (but keep simple)
  if ((k >= '0' && k <= '9') || k == '.' || k == ':' || (k >= 'A' && k <= 'Z') || (k >= 'a' && k <= 'z')) {
    if (inputIP.length() < 64) inputIP += k;
  }
}

// mouse press to focus ip box or click UI
void mousePressed() {
  // check ip box
  if (mouseX >= ipBoxX && mouseX <= ipBoxX + ipBoxW && mouseY >= ipBoxY && mouseY <= ipBoxY + ipBoxH) {
    typingIP = true;
  } else {
    typingIP = false;
  }
}

// ---------- host action handlers ----------
void hostHandleFlip(int player) {
  ArrayList<Card> from = (player == 1) ? p1 : p2;
  if (from.size() == 0) {
    localMsg = "No cards to flip!";
    return;
  }
  Card c = from.remove(0);
  PVector start = getTopOfDeckPosition(player);
  PVector end = getPileTopPositionHost();
  // start flip animation then onFinish push card to pile and flip turn & broadcast state
  anim.startFlipAnimation(c.copy(), start, end, new Runnable() {
    public void run() {
      pile.add(c);
      p1Turn = !p1Turn;
      copyToLocal();
      sendStateToAll();
    }
  });
}

void hostHandleSlap(int player) {
  if (pile.size() < 1) {
    anim.startSlapAnimation(player, false, new Runnable(){
      public void run() {
        resultText.show("BAD SLAP!", color(255, 100, 100));
        // penalty
        badSlapPenaltyHost(player);
        copyToLocal();
        sendStateToAll();
      }
    });
    return;
  }
  boolean isDouble = checkDoubleHost();
  boolean isSandwich = checkSandwichHost();
  boolean valid = isDouble || isSandwich;
  anim.startSlapAnimation(player, valid, new Runnable(){
    public void run() {
      if (valid) {
        if (isDouble) resultText.show("DOUBLE!", color(240,240,80));
        else resultText.show("SANDWICH!", color(160,240,160));
        ArrayList<Card> snapshot = new ArrayList<Card>(pile);
        pile.clear();
        PVector dest = getTopOfDeckPosition(player);
        anim.startCollectAnimation(snapshot, dest, player, new Runnable(){
          public void run() {
            ArrayList<Card> destList = (player == 1) ? p1 : p2;
            Collections.shuffle(snapshot, new Random());
            for (Card cc : snapshot) destList.add(cc);
            p1Turn = (player == 1);
            copyToLocal();
            sendStateToAll();
          }
        });
      } else {
        resultText.show("BAD SLAP!", color(255, 100, 100));
        badSlapPenaltyHost(player);
        copyToLocal();
        sendStateToAll();
      }
    }
  });
}

void badSlapPenaltyHost(int player) {
  ArrayList<Card> from = (player == 1) ? p1 : p2;
  if (from.size() > 0) {
    Card c = from.remove(0);
    pile.add(0, c);
  }
}

// ---------- host checks ----------
boolean checkDoubleHost() {
  if (pile.size() < 2) return false;
  return pile.get(pile.size()-1).rankValue == pile.get(pile.size()-2).rankValue;
}
boolean checkSandwichHost() {
  if (pile.size() < 3) return false;
  return pile.get(pile.size()-1).rankValue == pile.get(pile.size()-3).rankValue;
}

// ---------- networking: host start/stop ----------
void startHost() {
  try {
    netServer = new Server(this, NET_PORT);
    isHost = true;
    isClient = false;
    mode = "Host";
    connectionStatus = "Listening on port " + NET_PORT;
    clientID = -1;
    // host uses host state already created
    copyToLocal();
    // Send initial state periodically? host will broadcast after each action
  } catch (Exception e) {
    connectionStatus = "Failed to start server: " + e.getMessage();
  }
}

void stopHost() {
  if (netServer != null) {
    netServer.stop();
    netServer = null;
  }
  isHost = false;
  mode = "Idle";
  connectionStatus = "Host stopped";
}

// ---------- networking: client start/stop ----------
void startClient(String ip) {
  if (ip == null || ip.trim().length() == 0) {
    connectionStatus = "Enter host IP";
    return;
  }
  try {
    netClient = new Client(this, ip.trim(), NET_PORT);
    if (netClient.active()) {
      isClient = true;
      isHost = false;
      mode = "Client";
      connectionStatus = "Connected to " + ip.trim();
      hostIP = ip.trim();
      // ask host to send state
      netClient.write("HELLO\n");
    } else {
      connectionStatus = "Unable to connect";
    }
  } catch (Exception e) {
    connectionStatus = "Client error: " + e.getMessage();
  }
}

void stopClient() {
  if (netClient != null) {
    netClient.stop();
    netClient = null;
  }
  isClient = false;
  mode = "Idle";
  connectionStatus = "Client stopped";
}

// ---------- networking: handling client messages on host ----------
void handleNetMessageFromClient(Client c, String msg) {
  // expected messages: "HELLO", "FLIP", "SLAP"
  msg = msg.trim();
  if (msg.length() == 0) return;
  // assign client id if first connect
  if (clientID == -1) clientID = c.hashCode();
  if (msg.equals("HELLO")) {
    // send current state to this client
    sendStateToClient(c);
    connectionStatus = "Client connected: " + c.ip();
    return;
  }
  // only accept if not busy
  if (anim.isBusy()) {
    // ignore or queue; for now ignore
    return;
  }
  if (msg.equals("FLIP")) {
    // client is player 2
    hostHandleFlip(2);
  } else if (msg.equals("SLAP")) {
    hostHandleSlap(2);
  } else {
    println("Unknown from client: " + msg);
  }
}

// ---------- networking: handling host messages on client ----------
void handleNetMessageFromHost(String s) {
  // host will periodically send STATE messages terminated by newline.
  // Format:
  // STATE|p1DeckCSV|p2DeckCSV|pileCSV|turn|over|msg
  s = s.trim();
  if (s.length() == 0) return;
  if (s.startsWith("STATE|")) {
    String body = s.substring(6);
    String[] parts = split(body, '|');
    // Expect at least 6 parts
    if (parts.length >= 6) {
      localP1 = parseDeckCSV(parts[0]);
      localP2 = parseDeckCSV(parts[1]);
      localPile = parseDeckCSV(parts[2]);
      localP1Turn = parts[3].equals("1");
      localGameOver = parts[4].equals("1");
      localMsg = parts[5];
      // no direct animation triggers from incoming state — animations are triggered on host and broadcast
      copyToLocal(); // ensure local arrays set for rendering
    }
    return;
  } else if (s.equals("WELCOME")) {
    connectionStatus = "Welcome from host";
    return;
  } else {
    // other messages
    println("Msg from host: " + s);
  }
}

// ---------- send state (host broadcasts) ----------
void sendStateToAll() {
  // Build CSVs from p1,p2,pile
  String s1 = deckToCSV(p1);
  String s2 = deckToCSV(p2);
  String s3 = deckToCSV(pile);
  String turn = p1Turn ? "1" : "0";
  String over = gameOver ? "1" : "0";
  String msg = "OK";
  // full message:
  String stateMsg = "STATE|" + s1 + "|" + s2 + "|" + s3 + "|" + turn + "|" + over + "|" + msg + "\n";
  // send to all clients
  if (netServer != null) {
    netServer.write(stateMsg);
  }
  // also update local copies so the host UI sees the same
  copyToLocal();
}

// send to specific client (on initial HELLO)
void sendStateToClient(Client c) {
  String s1 = deckToCSV(p1);
  String s2 = deckToCSV(p2);
  String s3 = deckToCSV(pile);
  String turn = p1Turn ? "1" : "0";
  String over = gameOver ? "1" : "0";
  String msg = "OK";
  String stateMsg = "STATE|" + s1 + "|" + s2 + "|" + s3 + "|" + turn + "|" + over + "|" + msg + "\n";
  c.write(stateMsg);
}

// ---------- client send actions ----------
void sendClientAction(String action) {
  if (netClient == null || !netClient.active()) {
    connectionStatus = "Not connected";
    return;
  }
  netClient.write(action + "\n");
}

// ---------- serialization helpers ----------
String deckToCSV(ArrayList<Card> arr) {
  if (arr == null || arr.size() == 0) return "";
  String[] parts = new String[arr.size()];
  for (int i=0;i<arr.size();i++) {
    Card c = arr.get(i);
    parts[i] = c.rank + c.suit; // rank and suit together (e.g. "10♠", "A♥")
  }
  return join(parts, ',');
}
ArrayList<Card> parseDeckCSV(String csv) {
  ArrayList<Card> out = new ArrayList<Card>();
  if (csv == null || csv.trim().length() == 0) return out;
  String[] tokens = split(csv, ',');
  for (String t : tokens) {
    if (t.length() == 0) continue;
    // rank can be 1 or 2 chars (10) then 1 char suit maybe
    // we detect suits from known suit symbols
    String suits = "\u2660\u2665\u2666\u2663";
    char last = t.charAt(t.length()-1);
    if (suits.indexOf(last) >= 0) {
      String r = t.substring(0, t.length()-1);
      String su = "" + last;
      int val = rankToValue(r);
      out.add(new Card(r, su, val));
    } else {
      // fallback: assume last char is suit letter
      String r = t.substring(0, t.length()-1);
      String su = t.substring(t.length()-1);
      out.add(new Card(r, su, rankToValue(r)));
    }
  }
  return out;
}
int rankToValue(String r) {
  if (r.equals("A")) return 1;
  if (r.equals("J")) return 11;
  if (r.equals("Q")) return 12;
  if (r.equals("K")) return 13;
  try { return Integer.parseInt(r); } catch (Exception e) { return 0; }
}

// ---------- copy host state to local arrays (for display) ----------
void copyToLocal() {
  // For host this mirrors authoritative state to local display
  localP1 = deepCopyDeck(p1);
  localP2 = deepCopyDeck(p2);
  localPile = deepCopyDeck(pile);
  localP1Turn = p1Turn;
  localGameOver = gameOver;
}

ArrayList<Card> deepCopyDeck(ArrayList<Card> src) {
  ArrayList<Card> out = new ArrayList<Card>();
  if (src == null) return out;
  for (Card c: src) out.add(c.copy());
  return out;
}

// ---------- utility: get local IP ----------
String getLocalIP() {
  try {
    java.net.InetAddress local = java.net.InetAddress.getLocalHost();
    return local.getHostAddress();
  } catch (Exception e) {
    return "unknown";
  }
}

// ---------- helpers: positions ----------
PVector getTopOfDeckPosition(int player) {
  // positions in table coords: center region
  float tableW = width-420;
  float x;
  if (player == 1) x = 40 + CARD_W/2;
  else x = tableW - 40 - CARD_W/2;
  float y = 80 + (height-160)/2;
  return new PVector(200 + x, y); // +200 because table area translated earlier
}
PVector getPileTopPositionHost() {
  // pile position for host animations (same formula)
  float tableW = width-420;
  float x = 200 + tableW/2;
  float y = 80 + (height-160)/2;
  return new PVector(x, y);
}
PVector getPileTopPosition() {
  // for local animation overlays (uses the same host coordinates)
  return getPileTopPositionHost();
}

// ---------- CPU for host testing ----------
void handleCPUHost() {
  if (p1Turn) return;
  cpuWait++;
  if (cpuWait > 40) {
    cpuWait = 0;
    if (p2.size() > 0) hostHandleFlip(2);
  }
}

// ---------- Animation & helper classes (complete) ----------

// FadingText class
class FadingText {
  String txt = "";
  int col = color(255);
  int frame = 0;
  int total = 90;
  boolean active = false;
  void show(String s, int c) {
    txt = s; col = c; frame = 0; active = true;
  }
  void clear() { active = false; frame = 0; txt = ""; }
  void updateAndDraw() {
    if (!active) return;
    frame++;
    float alpha = 1.0;
    if (frame < 15) alpha = (float)frame/15.0;
    else if (frame > total - 15) alpha = max(0, (float)(total - frame)/15.0);
    else alpha = 1.0;
    if (frame >= total) active = false;
    pushMatrix();
    translate(width/2, 100);
    textAlign(CENTER, CENTER);
    textSize(32);
    fill(red(col), green(col), blue(col), 255*alpha);
    text(txt, 0, 0);
    popMatrix();
  }
}

// Card class
class Card {
  String rank, suit;
  int rankValue;
  Card(String r, String s, int v) { rank = r; suit = s; rankValue = v; }
  Card copy() { return new Card(rank, suit, rankValue); }
  void drawFace(float x, float y, float w, float h) {
    pushMatrix();
    translate(x, y);
    stroke(0); fill(255);
    rect(0,0,w,h,6);
    fill(0);
    textAlign(LEFT, TOP); textSize(16); text(rank + suit, 6, 6);
    textAlign(RIGHT, BOTTOM); text(rank + suit, w-6, h-6);
    textAlign(CENTER, CENTER); textSize(24); text(rank, w/2, h/2 - 8);
    textSize(12); text(suit, w/2, h/2 + 16);
    popMatrix();
  }
  void drawTransformed(float x, float y, float w, float h, float angDeg, float s) {
    pushMatrix(); translate(x, y); rotate(radians(angDeg)); scale(s);
    float cx = -w/2, cy = -h/2;
    stroke(0); fill(255); rect(cx, cy, w, h, 6);
    fill(0);
    textAlign(LEFT, TOP); textSize(16); text(rank + suit, cx + 6, cy + 6);
    textAlign(RIGHT, BOTTOM); text(rank + suit, cx + w - 6, cy + h - 6);
    textAlign(CENTER, CENTER); textSize(24); text(rank, cx + w/2, cy + h/2 - 8);
    textSize(12); text(suit, cx + w/2, cy + h/2 + 16);
    popMatrix();
  }
}

// AnimationManager and animations (flip + slap + collect)
class AnimationManager {
  ArrayList<AnimatedCard> overlays = new ArrayList<AnimatedCard>();
  SlapAnimation slapAnim = null;
  CollectAnimation collectAnim = null;
  boolean flipInProgress = false;
  Card flipPendingTopCard = null;

  void clear() { overlays.clear(); slapAnim=null; collectAnim=null; flipInProgress=false; flipPendingTopCard=null; }

  void update() {
    for (int i = overlays.size()-1; i >= 0; i--) {
      AnimatedCard ac = overlays.get(i);
      ac.update();
      if (ac.finished) {
        if (ac.onFinish != null) ac.onFinish.run();
        overlays.remove(i);
        if (ac.isFlip) { flipInProgress = false; flipPendingTopCard = null; }
      }
    }
    if (slapAnim != null) {
      slapAnim.update();
      if (slapAnim.finished) { if (slapAnim.onFinish!=null) slapAnim.onFinish.run(); slapAnim=null; }
    }
    if (collectAnim != null) {
      collectAnim.update();
      if (collectAnim.finished) { if (collectAnim.onFinish!=null) collectAnim.onFinish.run(); collectAnim=null; }
    }
  }

  void drawOverlays() {
    if (collectAnim != null) collectAnim.draw();
    for (AnimatedCard ac : overlays) ac.draw();
    if (slapAnim != null) slapAnim.draw();
  }

  boolean isBusy() { return flipInProgress || slapAnim != null || collectAnim != null || overlays.size() > 0; }

  void startFlipAnimation(Card c, PVector startCenter, PVector endCenter, Runnable onFinish) {
    if (flipInProgress) return;
    flipInProgress = true; flipPendingTopCard = c;
    AnimatedCard ac = new AnimatedCard(c, startCenter.copy(), endCenter.copy(), 16);
    ac.onFinish = onFinish; ac.isFlip = true; overlays.add(ac);
  }

  boolean isCardBeingFlipped() { return flipInProgress; }
  boolean flipPendingTopEquals(Card c) {
    if (flipPendingTopCard == null) return false;
    return (flipPendingTopCard.rank.equals(c.rank) && flipPendingTopCard.suit.equals(c.suit));
  }

  void startSlapAnimation(int player, boolean valid, Runnable onFinish) {
    if (slapAnim != null) return;
    slapAnim = new SlapAnimation(player, valid, onFinish);
  }

  PVector getPileShakeOffset() { if (slapAnim != null) return slapAnim.getCurrentShake(); return new PVector(0,0); }

  void startCollectAnimation(ArrayList<Card> snapshot, PVector destCenter, int winnerPlayer, Runnable onFinish) {
    if (collectAnim != null) return;
    collectAnim = new CollectAnimation(snapshot, destCenter, winnerPlayer, onFinish);
  }
}

class AnimatedCard {
  Card card; PVector from,to; int framesTotal, frame; boolean finished=false; Runnable onFinish=null; boolean isFlip=false;
  // rotation offset per flip
  float rotOffset = 0;
  AnimatedCard(Card c, PVector from, PVector to, int frames) {
    this.card=c; this.from=from; this.to=to; this.framesTotal=frames; this.frame=0;
    this.rotOffset = random(-12,12);
  }
  void update() { frame++; if (frame >= framesTotal) finished=true; }
  void draw() {
    float t = (float)frame / (float)framesTotal; t = easeOutCubic(t);
    float x = lerp(from.x, to.x, t); float y = lerp(from.y, to.y, t);
    float rot = lerp(rotOffset, 0, t);
    float s = 0.98 + 0.05 * sin(t * PI);
    card.drawTransformed(x, y, CARD_W, CARD_H, rot, s);
  }
  float easeOutCubic(float x) { return 1 - pow(1 - x, 3); }
}

class SlapAnimation {
  int totalFrames=28; int f=0; boolean finished=false; boolean valid; int player; Runnable onFinish=null;
  SlapAnimation(int player, boolean valid, Runnable onFinish) { this.player=player; this.valid=valid; this.onFinish=onFinish; }
  void update() { f++; if (f >= totalFrames) finished=true; }
  PVector getCurrentShake() {
    if (f < 6) { float p=(float)f/6.0; return new PVector(0, -10 + 10*(1-p)); }
    else if (f < 20) {
      float mag = valid ? 6 : 12;
      float x = sin(map(f,6,20,0,PI*6)) * mag * (1 - (float)(f-6)/14.0 * 0.5);
      float y = cos(map(f,6,20,0,PI*6)) * (mag/3.0);
      return new PVector(x,y);
    } else return new PVector(0,0);
  }
  void draw() {
    pushMatrix();
    PVector center = getPileTopPosition();
    translate(center.x, center.y - 20);
    float alpha = 0;
    if (f < 6) alpha = map(f, 0, 6, 0, 200);
    else if (f < 18) alpha = 200;
    else alpha = map(f, 18, totalFrames, 200, 0);
    noStroke(); fill(255, 255, 255, alpha);
    float scaleHand = 1.0 + 0.08 * sin(f*0.4);
    pushMatrix(); scale(scaleHand);
    beginShape(); vertex(-40, -20); vertex(-30, -30); vertex(-20, -28); vertex(-10, -38);
    vertex(0, -30); vertex(10, -32); vertex(20, -20); vertex(40, -10); vertex(20, 20); vertex(-20, 30); endShape(CLOSE);
    popMatrix();
    fill(255,255,255, alpha/3); ellipse(0, -10, 140 + f*0.2, 60 + f*0.2);
    popMatrix();
  }
}

class CollectAnimation {
  ArrayList<Card> flying; ArrayList<PVector> starts; PVector dest; int totalFrames=40; int f=0; boolean finished=false; int winnerPlayer; Runnable onFinish=null;
  CollectAnimation(ArrayList<Card> snapshot, PVector destCenter, int winnerPlayer, Runnable onFinish) {
    this.flying = snapshot; this.starts = new ArrayList<PVector>(); this.dest = destCenter.copy(); this.winnerPlayer = winnerPlayer; this.onFinish = onFinish;
    PVector pileCenter = getPileTopPosition();
    for (int i=0;i<flying.size();i++) {
      float offx = map(i, 0, max(1, flying.size()-1), -30, 30) + random(-6,6);
      float offy = map(i, 0, max(1, flying.size()-1), 30, -30) + random(-6,6);
      starts.add(new PVector(pileCenter.x + offx, pileCenter.y + offy));
    }
  }
  void update() { f++; if (f >= totalFrames) finished=true; }
  void draw() {
    for (int i=0;i<flying.size();i++) {
      Card c = flying.get(i); PVector s = starts.get(i);
      float t = (float)f / (float)totalFrames; t = easeOutQuad(t);
      float x = lerp(s.x, dest.x, t); float y = lerp(s.y, dest.y, t);
      float sscale = lerp(1.0, 0.5, t);
      float rot = lerp(0, (i%2==0? -20:20), t) * (1 - t);
      c.drawTransformed(x, y, CARD_W, CARD_H, rot, sscale);
    }
  }
  float easeOutQuad(float x) { return 1 - (1-x)*(1-x); }
}

// ---------- Game logic helpers ----------
boolean checkDoubleHost2(ArrayList<Card> deckcheck) {
  if (deckcheck.size() < 2) return false;
  return deckcheck.get(deckcheck.size()-1).rankValue == deckcheck.get(deckcheck.size()-2).rankValue;
}

// ---------- helpers: conversion ----------
String deckToCSVLocal(ArrayList<Card> arr) {
  if (arr == null || arr.size() == 0) return "";
  String[] parts = new String[arr.size()];
  for (int i=0;i<arr.size();i++) {
    Card c = arr.get(i);
    parts[i] = c.rank + c.suit;
  }
  return join(parts, ',');
}

// ---------- misc ----------

// ---------- End of file ----------
