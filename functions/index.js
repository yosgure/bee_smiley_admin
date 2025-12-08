import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart'; // 最新版の入力機能
import 'package:flame/input.dart';  // 念のための予備
import 'package:flutter/material.dart';

void main() {
  runApp(GameWidget(game: CubeGame()));
}

class CubeGame extends FlameGame with PanDetector, TapDetector {
  // --- 設定 ---
  static const int columns = 5;
  static const int rows = 12;
  static const double cellSize = 60.0;
  
  late Vector2 gridOffset;

  // プレイヤー情報
  int playerCol = 2;
  int playerRow = 11;
  late RectangleComponent player;

  // 床の管理
  List < List < RectangleComponent >> floorTiles =[];

  @override
  Color backgroundColor() => const Color(0xFF111111);

  @override
  Future < void> onLoad() async {
    // 画面中央配置の計算
    final gridWidth = columns * cellSize;
    final gridHeight = rows * cellSize;
    gridOffset = Vector2(
      (size.x - gridWidth) / 2,
      (size.y - gridHeight) / 2,
    );

    // 1. 床を描画
    for (int row = 0; row < rows; row++) {
      List < RectangleComponent > rowTiles =[];
      for (int col = 0; col < columns; col++) {
        final tile = RectangleComponent(
        position: _getGridPosition(col, row),
        size: Vector2(cellSize - 2, cellSize - 2),
        paint: Paint()
          ..color = (row + col) % 2 == 0
        ? const Color(0xFF333333) 
                : const Color(0xFF222222),
        );
        add(tile);
        rowTiles.add(tile);
      }
      floorTiles.add(rowTiles);
    }

    // 2. プレイヤーを配置
    playerCol = (columns / 2).floor();
    playerRow = rows - 1;

    player = RectangleComponent(
      position: _getGridPosition(playerCol, playerRow) + Vector2(5, 5),
      size: Vector2(cellSize - 10, cellSize - 10),
      paint: Paint()..color = Colors.blueAccent,
    );
    add(player);
  }

  // --- 操作（入力）の処理 ---

  @override
  void onPanEnd(DragEndInfo info) {
    // スワイプ判定
    final velocity = info.velocity;
    if (velocity.x.abs() > velocity.y.abs()) {
      if (velocity.x > 0) movePlayer(1, 0); // 右
      else movePlayer(-1, 0); // 左
    } else {
      if (velocity.y > 0) movePlayer(0, 1); // 手前
      else movePlayer(0, -1); // 奥
    }
  }

  @override
  void onTap() {
    // タップ判定（床の色変え）
    final tile = floorTiles[playerRow][playerCol];
    if (tile.paint.color == Colors.yellowAccent) {
      tile.paint.color = (playerRow + playerCol) % 2 == 0
        ? const Color(0xFF333333) 
          : const Color(0xFF222222);
    } else {
      tile.paint.color = Colors.yellowAccent;
    }
  }

  void movePlayer(int dx, int dy) {
    int newCol = playerCol + dx;
    int newRow = playerRow + dy;

    // 画面外に出ないようにチェック
    if (newCol >= 0 && newCol < columns && newRow >= 0 && newRow < rows) {
      playerCol = newCol;
      playerRow = newRow;
      player.position = _getGridPosition(playerCol, playerRow) + Vector2(5, 5);
    }
  }

  Vector2 _getGridPosition(int col, int row) {
    return gridOffset + Vector2(col * cellSize, row * cellSize);
  }
}