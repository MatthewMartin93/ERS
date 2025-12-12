// ERS_SingleFile_Fixed.pde
// Single-file Processing 4.3 compatible version
// Flip style B: slide + slight rotation
// Flip, slap, collect animations included.
// Controls: P1 flip A slap S, P2 flip L slap K, Space pause, R restart

import java.util.*;

final int CARD_W = 70;
final int CARD_H = 100;

// --------- FadingText (defined first to avoid tab-order issues) ----------
class FadingText {
  String txt = "";
  int col = color(255);
  int frame = 0;
  int total = 90;
  boolean active = false;

  void show(String s, int c) {
    txt = s;
    col = c;
    frame = 0;
    active = true;
  }
  void clear() {
    active = false;
    frame = 0;
    txt = "";
  }

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

// --------- Card class ----------
class Card {
  String rank, suit;
  int rankValue;
  Card(String r, String s, int v) {
    rank = r; suit = s; rankValue = v;
  }
  Card copy() {
    return new Card(rank, suit, rankValue);
  }
  void drawFace(float x, float y, float w, float h) {
    pushMatrix();
    translate(x, y);
    stroke(0);
    fill(255);
    rect(0, 0, w, h, 6);
    fill(0);
    textAlign(LEFT, TOP);
    textSize(16);
    text(rank + suit, 6, 6);
    textAlign(RIGHT, BOTTOM);
    text(rank + suit, w - 6, h - 6);
    textAlign(CENTER, CENTER);
    textSize(24);
    text(rank, w/2, h/2 - 8);
    textSize(12);
    text(suit, w/2, h/2 + 16);
    popMatrix();
  }
  void drawTransformed(float x, float y, float w, float h, float angDeg, float s) {
    pushMatrix();
    translate(x, y);
    rotate(radians(angDeg));
    scale(s);
    float cx = -w/2;
    float cy = -h/2;
    stroke(0);
    fill(255);
    rect(cx, cy, w, h, 6);
    fill(0);
    textAlign(LEFT, TOP);
    textSize(16);
    text(rank + suit, cx + 6, cy + 6);
    textAlign(RIGHT, BOTTOM);
    text(rank + suit, cx + w - 6, cy + h - 6);
    textAlign(CENTER, CENTER);
    textSize(24);
    text(rank, cx + w/2, cy + h/2 - 8);
    textSize(12);
    text(suit, cx + w/2, cy + h/2 + 16);
    popMatrix();
  }
}

// --------- AnimationManager and animations ----------
class AnimationManager {
  ArrayList<AnimatedCard> overlays = new ArrayList<AnimatedCard>();
  SlapAnimation slapAnim = null;
  CollectAnimation collectAnim = null;
  boolean flipInProgress = false;
  Card flipPendingTopCard = null;

  void clear() {
    overlays.clear();
    slapAnim = null;
    collectAnim = null;
    flipInProgress = false;
    flipPendingTopCard = null;
  }

  void update() {
    for (int i = overlays.size()-1; i >= 0; i--) {
      AnimatedCard ac = overlays.get(i);
      ac.update();
      if (ac.finished) {
        if (ac.onFinish != null) ac.onFinish.run();
        overlays.remove(i);
        if (ac.isFlip) {
          flipInProgress = false;
          flipPendingTopCard = null;
        }
      }
    }
    if (slapAnim != null) {
      slapAnim.update();
      if (slapAnim.finished) {
        if (slapAnim.onFinish != null) slapAnim.onFinish.run();
        slapAnim = null;
      }
    }
    if (collectAnim != null) {
      collectAnim.update();
      if (collectAnim.finished) {
        if (collectAnim.onFinish != null) collectAnim.onFinish.run();
        collectAnim = null;
      }
    }
  }

  void drawOverlays() {
    if (collectAnim != null) collectAnim.draw();
    for (AnimatedCard ac : overlays) ac.draw();
    if (slapAnim != null) slapAnim.draw();
  }

  boolean isBusy() {
    return flipInProgress || slapAnim != null || collectAnim != null || overlays.size() > 0;
  }

  void startFlipAnimation(Card c, PVector startCenter, PVector endCenter, Runnable onFinish) {
    if (flipInProgress) return;
    flipInProgress = true;
    flipPendingTopCard = c;
    AnimatedCard ac = new AnimatedCard(c, startCenter.copy(), endCenter.copy(), 16);
    ac.onFinish = onFinish;
    ac.isFlip = true;
    overlays.add(ac);
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

  PVector getPileShakeOffset() {
    if (slapAnim != null) return slapAnim.getCurrentShake();
    return new PVector(0, 0);
  }

  void startCollectAnimation(ArrayList<Card> snapshot, PVector destCenter, int winnerPlayer, Runnable onFinish) {
    if (collectAnim != null) return;
    collectAnim = new CollectAnimation(snapshot, destCenter, winnerPlayer, onFinish);
  }
}

class AnimatedCard {
  Card card;
  PVector from, to;
  int framesTotal;
  int frame;
  boolean finished = false;
  Runnable onFinish = null;
  boolean isFlip = false;

  AnimatedCard(Card c, PVector from, PVector to, int frames) {
    this.card = c;
    this.from = from;
    this.to = to;
    this.framesTotal = frames;
    this.frame = 0;
  }

  void update() {
    frame++;
    if (frame >= framesTotal) finished = true;
  }

  void draw() {
    float t = (float)frame / (float)framesTotal;
    t = easeOutCubic(t);
    float x = lerp(from.x, to.x, t);
    float y = lerp(from.y, to.y, t);
    float rotMax = 8;
    float rot = rotMax * (1 - t) * (sin(t*PI*2) * 0.5);
    float s = 0.98 + 0.05 * sin(t * PI);
    card.drawTransformed(x, y, CARD_W, CARD_H, rot, s);
  }

  float easeOutCubic(float x) {
    return 1 - pow(1 - x, 3);
  }
}

class SlapAnimation {
  int totalFrames = 28;
  int f = 0;
  boolean finished = false;
  boolean valid;
  int player;
  Runnable onFinish = null;
  SlapAnimation(int player, boolean valid, Runnable onFinish) {
    this.player = player;
    this.valid = valid;
    this.onFinish = onFinish;
  }
  void update() {
    f++;
    if (f >= totalFrames) finished = true;
  }
  PVector getCurrentShake() {
    if (f < 6) {
      float p = (float)f/6.0;
      float x = 0;
      float y = -10 + 10*(1-p);
      return new PVector(x, y);
    } else if (f < 20) {
      float mag = valid ? 6 : 12;
      float x = sin(map(f,6,20,0,PI*6)) * mag * (1 - (float)(f-6)/14.0 * 0.5);
      float y = cos(map(f,6,20,0,PI*6)) * (mag/3.0);
      return new PVector(x, y);
    } else {
      return new PVector(0, 0);
    }
  }
  void draw() {
    pushMatrix();
    PVector center = new PVector(width/2, height/2);
    translate(center.x, center.y - 20);
    float alpha = 0;
    if (f < 6) alpha = map(f, 0, 6, 0, 200);
    else if (f < 18) alpha = 200;
    else alpha = map(f, 18, totalFrames, 200, 0);
    noStroke();
    fill(255, 255, 255, alpha);
    float scaleHand = 1.0 + 0.08 * sin(f*0.4);
    pushMatrix();
    scale(scaleHand);
    beginShape();
    vertex(-40, -20);
    vertex(-30, -30);
    vertex(-20, -28);
    vertex(-10, -38);
    vertex(0, -30);
    vertex(10, -32);
    vertex(20, -20);
    vertex(40, -10);
    vertex(20, 20);
    vertex(-20, 30);
    endShape(CLOSE);
    popMatrix();
    fill(255, 255, 255, alpha/3);
    ellipse(0, -10, 140 + f*0.2, 60 + f*0.2);
    popMatrix();
  }
}

class CollectAnimation {
  ArrayList<Card> flying;
  ArrayList<PVector> starts;
  PVector dest;
  int totalFrames = 40;
  int f = 0;
  boolean finished = false;
  int winnerPlayer;
  Runnable onFinish = null;

  CollectAnimation(ArrayList<Card> snapshot, PVector destCenter, int winnerPlayer, Runnable onFinish) {
    this.flying = snapshot;
    this.starts = new ArrayList<PVector>();
    this.dest = destCenter.copy();
    this.winnerPlayer = winnerPlayer;
    this.onFinish = onFinish;
    PVector pileCenter = getPileTopPosition();
    for (int i=0; i<flying.size(); i++) {
      float offx = map(i, 0, max(1, flying.size()-1), -30, 30) + random(-6,6);
      float offy = map(i, 0, max(1, flying.size()-1), 30, -30) + random(-6,6);
      starts.add(new PVector(pileCenter.x + offx, pileCenter.y + offy));
    }
  }

  void update() {
    f++;
    if (f >= totalFrames) finished = true;
  }

  void draw() {
    for (int i=0; i<flying.size(); i++) {
      Card c = flying.get(i);
      PVector s = starts.get(i);
      float t = (float)f / (float)totalFrames;
      t = easeOutQuad(t);
      float x = lerp(s.x, dest.x, t);
      float y = lerp(s.y, dest.y, t);
      float sscale = lerp(1.0, 0.5, t);
      float rot = lerp(0, (i%2==0? -20:20), t) * (1 - t);
      c.drawTransformed(x, y, CARD_W, CARD_H, rot, sscale);
    }
  }

  float easeOutQuad(float x) { return 1 - (1-x)*(1-x); }
}

// ---------- Game State ----------
ArrayList<Card> deck;
ArrayList<Card> pile = new ArrayList<Card>();
ArrayList<Card> p1 = new ArrayList<Card>();
ArrayList<Card> p2 = new ArrayList<Card>();

boolean p1Turn = true;
boolean paused = false;
boolean gameOver = false;

boolean cpuMode = false;
int cpuReaction = 25;

AnimationManager anim;
FadingText resultText;
String persistentMsg = "Press A/L to flip, S/K to slap. R to restart.";

// ---------- Setup ----------
void settings() {
  size(900, 520);
}
void setup() {
  textFont(createFont("Arial", 14));
  anim = new AnimationManager();
  resultText = new FadingText();
  initGame();
}

void initGame() {
  deck = new ArrayList<Card>();
  pile.clear();
  p1.clear();
  p2.clear();
  gameOver = false;
  p1Turn = true;
  persistentMsg = "Press A/L to flip, S/K to slap. R to restart.";
  resultText.clear();
  anim.clear();

  String[] suits = {"\u2660","\u2665","\u2666","\u2663"};
  String[] ranks = {"A","2","3","4","5","6","7","8","9","10","J","Q","K"};
  for (String s : suits) {
    for (int i=0; i<ranks.length; i++){
      deck.add(new Card(ranks[i], s, i+1));
    }
  }
  Collections.shuffle(deck, new Random());
  deal();
}

void deal() {
  for (int i=0; i<deck.size(); i++) {
    if (i%2==0) p1.add(deck.get(i));
    else p2.add(deck.get(i));
  }
  deck.clear();
}

// ---------- Draw ----------
void draw() {
  background(40, 150, 60);
  drawTable();

  if (paused) {
    fill(0, 150);
    rect(0,0,width,height);
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(30);
    text("PAUSED", width/2, height/2);
    return;
  }

  anim.update();

  if (cpuMode && !gameOver && !anim.isBusy()) handleCPU();

  fill(255);
  textAlign(CENTER);
  textSize(14);
  text(persistentMsg, width/2, 30);

  resultText.updateAndDraw();

  checkGameOver();
}

void drawTable() {
  pushMatrix();
  translate(80, height/2);
  drawPlayerArea(p1, "Player 1", p1Turn && !gameOver);
  popMatrix();

  pushMatrix();
  translate(width - 80 - CARD_W, height/2);
  drawPlayerArea(p2, "Player 2", !p1Turn && !gameOver);
  popMatrix();

  pushMatrix();
  translate(width/2 - CARD_W/2, height/2 - CARD_H/2);
  PVector shake = anim.getPileShakeOffset();
  translate(shake.x, shake.y);
  drawPile();
  popMatrix();

  anim.drawOverlays();
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

void drawPile() {
  fill(0, 0, 0, 30);
  rect(-10, -10, CARD_W+20, CARD_H+20, 6);
  if (pile.size() == 0) {
    fill(255);
    rect(0, 0, CARD_W, CARD_H, 6);
    fill(0);
    textAlign(CENTER, CENTER);
    text("Pile", CARD_W/2, CARD_H/2);
    return;
  }
  int show = min(pile.size(), 8);
  for (int i=0; i<show; i++) {
    Card c = pile.get(pile.size()-show + i);
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

// ---------- Input ----------
void keyPressed() {
  if (key == 'r' || key == 'R') { initGame(); return; }
  if (key == ' ') { paused = !paused; return; }
  if (paused || gameOver) return;
  if (anim.isBusy()) return;

  if ((key == 'A' || key == 'a') && p1Turn) playerFlip(1);
  else if ((key == 'S' || key == 's')) playerSlap(1);

  if ((key == 'L' || key == 'l') && !p1Turn) playerFlip(2);
  else if ((key == 'K' || key == 'k')) playerSlap(2);
}

// ---------- Actions ----------
void playerFlip(int player) {
  ArrayList<Card> from = (player == 1) ? p1 : p2;
  if (from.size() == 0) {
    persistentMsg = "Player " + player + " has no cards to flip!";
    return;
  }
  Card c = from.remove(0);
  PVector start = getTopOfDeckPosition(player);
  PVector end = getPileTopPosition();
  anim.startFlipAnimation(c.copy(), start, end, new Runnable() {
    public void run() {
      pile.add(c);
      p1Turn = !p1Turn;
    }
  });
}

void playerSlap(int player) {
  if (pile.size() < 1) {
    anim.startSlapAnimation(player, false, new Runnable(){
      public void run() {
        resultText.show("BAD SLAP!", color(255, 100, 100));
        badSlapPenalty(player);
      }
    });
    return;
  }

  boolean isDouble = checkDouble();
  boolean isSandwich = checkSandwich();
  boolean valid = isDouble || isSandwich;

  anim.startSlapAnimation(player, valid, new Runnable(){
    public void run() {
      if (valid) {
        if (isDouble) resultText.show("DOUBLE!", color(240, 240, 80));
        else resultText.show("SANDWICH!", color(160, 240, 160));
        ArrayList<Card> snapshot = new ArrayList<Card>(pile);
        pile.clear();
        PVector dest = getTopOfDeckPosition(player);
        anim.startCollectAnimation(snapshot, dest, player, new Runnable(){
          public void run() {
            ArrayList<Card> destList = (player == 1) ? p1 : p2;
            Collections.shuffle(snapshot, new Random());
            for (Card cc : snapshot) destList.add(cc);
            p1Turn = (player == 1);
          }
        });
      } else {
        resultText.show("BAD SLAP!", color(255, 100, 100));
        badSlapPenalty(player);
      }
    }
  });
}

void badSlapPenalty(int player) {
  ArrayList<Card> from = (player == 1) ? p1 : p2;
  if (from.size() > 0) {
    Card c = from.remove(0);
    pile.add(0, c);
  }
}

// ---------- Helpers ----------
PVector getTopOfDeckPosition(int player) {
  float x = (player == 1) ? (80 + CARD_W/2) : (width - 80 - CARD_W/2);
  float y = height/2;
  return new PVector(x, y);
}
PVector getPileTopPosition() {
  return new PVector(width/2, height/2);
}

boolean checkDouble() {
  if (pile.size() < 2) return false;
  return pile.get(pile.size()-1).rankValue == pile.get(pile.size()-2).rankValue;
}
boolean checkSandwich() {
  if (pile.size() < 3) return false;
  return pile.get(pile.size()-1).rankValue == pile.get(pile.size()-3).rankValue;
}

// ---------- CPU ----------
int cpuWait = 0;
void handleCPU() {
  if (p1Turn || gameOver || anim.isBusy()) return;
  if ((checkDouble() || checkSandwich())) {
    if (random(100) < (100 - cpuReaction)) {
      playerSlap(2);
      return;
    }
  }
  cpuWait++;
  if (cpuWait > 40) {
    cpuWait = 0;
    if (p2.size() > 0) playerFlip(2);
  }
}

// ---------- Game over ----------
void checkGameOver() {
  if (gameOver) return;
  if (p1.size() == 0 && p2.size() == 0 && pile.size() == 0) {
    gameOver = true;
    persistentMsg = "Draw! R to restart.";
  } else if (p1.size() == 0 && pile.size() == 0) {
    gameOver = true;
    persistentMsg = "Player 2 wins! R to restart.";
  } else if (p2.size() == 0 && pile.size() == 0) {
    gameOver = true;
    persistentMsg = "Player 1 wins! R to restart.";
  }
}
