//
//  HRYMyScene.m
//  CookieCrunch
//
//  Created by Ryoichi Hara on 2014/06/10.
//  Copyright (c) 2014年 Ryoichi Hara. All rights reserved.
//

#import "HRYMyScene.h"
#import "HRYCookie.h"
#import "HRYLevel.h"
#import "HRYSwap.h"
#import "HRYChain.h"

static const CGFloat kTileWidth  = 32.0f;
static const CGFloat kTileHeight = 36.0f;

@interface HRYMyScene ()

@property (nonatomic, strong) SKNode *gameLayer;
@property (nonatomic, strong) SKNode *cookiesLayer;
@property (nonatomic, strong) SKNode *tilesLayer;
@property (nonatomic, assign) NSInteger swipeFromColumn;
@property (nonatomic, assign) NSInteger swipeFromRow;
@property (nonatomic, strong) SKSpriteNode *selectionSprite;

@property (nonatomic, strong) SKCropNode *cropLayer;
@property (nonatomic, strong) SKNode *maskLayer;

// Sound Effetcs
@property (nonatomic, strong) SKAction *swapSound;
@property (nonatomic, strong) SKAction *invalidSwapSound;
@property (nonatomic, strong) SKAction *matchSound;
@property (nonatomic, strong) SKAction *failingCookieSound;
@property (nonatomic, strong) SKAction *addCookieSound;

@end

@implementation HRYMyScene

#pragma mark - Lifecycle

- (instancetype)initWithSize:(CGSize)size {
    self = [super initWithSize:size];

    if (self) {
        self.anchorPoint = CGPointMake(0.5f, 0.5f);

        SKSpriteNode *background = [SKSpriteNode spriteNodeWithImageNamed:@"Background"];
        [self addChild:background];

        _gameLayer = [SKNode node];
        [self addChild:_gameLayer];

        _gameLayer.hidden = YES;

        CGPoint layerPosition = CGPointMake(
            -(kTileWidth * HRYLevelNumColumns) / 2,
            -(kTileHeight * HRYLevelNumRows) / 2
        );

        _tilesLayer = [SKNode node];
        _tilesLayer.position = layerPosition;
        [_gameLayer addChild:_tilesLayer];

        _cropLayer = [SKCropNode node];
        [_gameLayer addChild:_cropLayer];

        _maskLayer = [SKNode node];
        _maskLayer.position = layerPosition;

        // A crop node only draws its children where the mask contains pixels
        _cropLayer.maskNode = _maskLayer;

        _cookiesLayer = [SKNode node];
        _cookiesLayer.position = layerPosition;

        [_cropLayer addChild:_cookiesLayer];

        _swipeFromColumn = _swipeFromRow = NSNotFound;

        _selectionSprite = [SKSpriteNode node];

        [self p_preloadResources];
    }

    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInNode:self.cookiesLayer];

    NSInteger column, row;

    // Check whether the touch is inside a square on the level grid, or not.
    if ([self p_convertPoint:location toColumn:&column row:&row]) {
        HRYCookie *cookie = [self.level cookieAtColumn:column row:row];

        // Verify that the touch is on a cookie rather than on an empty square
        if (cookie) {
            [self p_showSelectionIndicatorForCookie:cookie];

            // Record the start point of a swipe motion
            self.swipeFromColumn = column;
            self.swipeFromRow = row;
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    // Either the swipe began outside the valid area or the game has already swapped the cookies
    if (self.swipeFromColumn == NSNotFound) return;

    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInNode:self.cookiesLayer];

    NSInteger column, row;

    if ([self p_convertPoint:location toColumn:&column row:&row]) {
        NSInteger horzDelta = 0, vertDelta = 0;

        if (column < self.swipeFromColumn) {       // Swiping left
            horzDelta = -1;
        }
        else if (column > self.swipeFromColumn) {  // Swiping right
            horzDelta = 1;
        }
        else if (row < self.swipeFromRow) {        // Swiping down
            vertDelta = -1;
        }
        else if (row > self.swipeFromRow) {        // Swiping up
            vertDelta = 1;
        }

        if (horzDelta != 0 || vertDelta != 0) {
            // Perform the swap if the player swiped out of the old square
            [self p_trySwapHorizontal:horzDelta vertical:vertDelta];

            [self p_hideSelectionIndicator];

            // The game will ignore the rest of this swipe motion
            self.swipeFromColumn = NSNotFound;
        }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    self.swipeFromColumn = self.swipeFromRow = NSNotFound;

    if (self.selectionSprite.parent && self.swipeFromColumn != NSNotFound) {
        [self p_hideSelectionIndicator];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    self.swipeFromColumn = self.swipeFromRow = NSNotFound;
}

#pragma mark - Public

- (void)addSpritesForCookies:(NSSet *)cookies {
    for (HRYCookie *cookie in cookies) {
        SKSpriteNode *sprite =[SKSpriteNode spriteNodeWithImageNamed:[cookie spriteName]];
        sprite.position = [self p_pointForColumn:cookie.column row:cookie.row];
        [self.cookiesLayer addChild:sprite];

        cookie.sprite = sprite;
        cookie.sprite.alpha = 0.0f;
        [cookie.sprite setScale:0.5f];

        [cookie.sprite runAction:[SKAction sequence:@[
            [SKAction waitForDuration:0.25 withRange:0.5],
            [SKAction group:@[
                [SKAction fadeInWithDuration:0.25],
                [SKAction scaleTo:1.0f duration:0.25]
            ]]
        ]]];
    }
}

- (void)addTiles {
    for (NSInteger row = 0; row < HRYLevelNumRows; row++) {

        for (NSInteger column = 0; column < HRYLevelNumColumns; column++) {

            if ([self.level tileAtColumn:column row:row]) {
                SKSpriteNode *tileNode = [SKSpriteNode spriteNodeWithImageNamed:@"MaskTile"];
                tileNode.position = [self p_pointForColumn:column row:row];

                [self.maskLayer addChild:tileNode];
            }
        }
    }

    for (NSInteger row = 0; row <= HRYLevelNumRows; row++) {

        for (NSInteger column = 0; column <= HRYLevelNumColumns; column++) {
            BOOL topLeft = (column > 0) &&
                (row < HRYLevelNumRows) && [self.level tileAtColumn:column - 1 row:row];
            BOOL bottomLeft = (column > 0) &&
                (row > 0) && [self.level tileAtColumn:column - 1 row:row - 1];
            BOOL topRight = (column < HRYLevelNumColumns) &&
                (row < HRYLevelNumRows) && [self.level tileAtColumn:column row:row];
            BOOL bottomRight = (column < HRYLevelNumColumns) &&
                (row > 0) && [self.level tileAtColumn:column row:row - 1];

            // The tiles are named from 0 to 15, according to the bitmask that is
            // made by combining these four values.
            NSUInteger value = topLeft | topRight << 1 | bottomLeft << 2 | bottomRight << 3;

            // Values 0 (no tiles), 6 and 9 (two opposite tiles) are not drawn.
            if (value != 0 && value != 6 && value != 9) {
                NSString *name = [NSString stringWithFormat:@"Tile_%lu", (long)value];
                SKSpriteNode *tileNode = [SKSpriteNode spriteNodeWithImageNamed:name];
                CGPoint point = [self p_pointForColumn:column row:row];
                point.x -= kTileWidth / 2;
                point.y -= kTileHeight / 2;
                tileNode.position = point;
                [self.tilesLayer addChild:tileNode];
            }
        }
    }
}

- (void)animateSwap:(HRYSwap *)swap completion:(dispatch_block_t)completion {
    // Put the cookie you started with on top.
    swap.cookieA.sprite.zPosition = 100.0f;
    swap.cookieB.sprite.zPosition = 90.0f;

    const NSTimeInterval duration = 0.3;

    SKAction *moveA = [SKAction moveTo:swap.cookieB.sprite.position duration:duration];
    moveA.timingMode = SKActionTimingEaseOut;

    [swap.cookieA.sprite runAction:[SKAction sequence:@[moveA, [SKAction runBlock:completion]]]];

    SKAction *moveB = [SKAction moveTo:swap.cookieA.sprite.position duration:duration];
    moveB.timingMode = SKActionTimingEaseOut;

    [swap.cookieB.sprite runAction:moveB];

    [self runAction:self.swapSound];
}

- (void)animateInvalidSwap:(HRYSwap *)swap completion:(dispatch_block_t)completion {
    swap.cookieA.sprite.zPosition = 100.0f;
    swap.cookieB.sprite.zPosition = 90.0f;

    const NSTimeInterval duration = 0.2;

    SKAction *moveA = [SKAction moveTo:swap.cookieB.sprite.position duration:duration];
    moveA.timingMode = SKActionTimingEaseOut;

    SKAction *moveB = [SKAction moveTo:swap.cookieA.sprite.position duration:duration];
    moveB.timingMode = SKActionTimingEaseOut;

    [swap.cookieA.sprite runAction:[SKAction sequence:@[moveA, moveB, [SKAction runBlock:completion]]]];
    [swap.cookieB.sprite runAction:[SKAction sequence:@[moveB, moveA]]];

    [self runAction:self.invalidSwapSound];
}

- (void)animateMatchedCookies:(NSSet *)chains completion:(dispatch_block_t)completion {
    for (HRYChain *chain in chains) {

        [self p_animateScoreForChain:chain];

        for (HRYCookie *cookie in chain.cookies) {

            if (cookie.sprite) {
                SKAction *scaleAction = [SKAction scaleTo:0.1f duration:0.3];
                scaleAction.timingMode = SKActionTimingEaseOut;
                [cookie.sprite runAction:[SKAction sequence:@[scaleAction, [SKAction removeFromParent]]]];
            }
        }
    }

    [self runAction:self.matchSound];

    [self runAction:[SKAction sequence:@[[SKAction waitForDuration:0.3], [SKAction runBlock:completion]]]];
}

- (void)animateFallingCookies:(NSArray *)columns completion:(dispatch_block_t)completion {
    __block NSTimeInterval longestDuration = 0.0;

    for (NSArray *array in columns) {
        [array enumerateObjectsUsingBlock:^(HRYCookie *cookie, NSUInteger idx, BOOL *stop) {
            CGPoint newPosition = [self p_pointForColumn:cookie.column row:cookie.row];
            NSTimeInterval delay = 0.05 + (0.15 * idx);
            NSTimeInterval duration = ((cookie.sprite.position.y - newPosition.y) / kTileHeight) * 0.1;

            longestDuration = MAX(longestDuration, duration + delay);

            SKAction *moveAction = [SKAction moveTo:newPosition duration:duration];
            moveAction.timingMode = SKActionTimingEaseOut;

            [cookie.sprite runAction:[SKAction sequence:@[
                [SKAction waitForDuration:delay],
                [SKAction group:@[moveAction, self.failingCookieSound]]
            ]]];
        }];
    }

    [self runAction:[SKAction sequence:@[
        [SKAction waitForDuration:longestDuration],
        [SKAction runBlock:completion]
    ]]];
}

- (void)animateNewCookies:(NSArray *)columns completion:(dispatch_block_t)completion {
    __block NSTimeInterval longestDuration = 0.0;

    for (NSArray *array in columns) {
        NSInteger startRow = ((HRYCookie *)[array firstObject]).row + 1;

        [array enumerateObjectsUsingBlock:^(HRYCookie *cookie, NSUInteger idx, BOOL *stop) {
            SKSpriteNode *sprite = [SKSpriteNode spriteNodeWithImageNamed:[cookie spriteName]];
            sprite.position = [self p_pointForColumn:cookie.column row:startRow];

            [self.cookiesLayer addChild:sprite];
            cookie.sprite = sprite;

            NSTimeInterval delay = 0.1 + 0.2 * ([array count] - idx - 1);
            NSTimeInterval duration = (startRow - cookie.row) * 0.1;

            longestDuration = MAX(longestDuration, duration + delay);

            CGPoint newPosition = [self p_pointForColumn:cookie.column row:cookie.row];
            SKAction *moveAction = [SKAction moveTo:newPosition duration:duration];
            moveAction.timingMode = SKActionTimingEaseOut;

            cookie.sprite.alpha = 0.0f;

            [cookie.sprite runAction:[SKAction sequence:@[
                [SKAction waitForDuration:delay],
                [SKAction group:@[
                    [SKAction fadeInWithDuration:0.05],
                    moveAction,
                    self.addCookieSound
                ]]
            ]]];
        }];
    }

    [self runAction:[SKAction sequence:@[
        [SKAction waitForDuration:longestDuration],
        [SKAction runBlock:completion]
    ]]];
}

- (void)animateGameOver {
    SKAction *action = [SKAction moveBy:CGVectorMake(0.0f, -self.size.height) duration:0.3];
    action.timingMode = SKActionTimingEaseIn;
    [self.gameLayer runAction:action];
}

- (void)animateBeginGame {
    self.gameLayer.hidden = NO;

    self.gameLayer.position = CGPointMake(0.0f, self.size.height);
    SKAction *action = [SKAction moveBy:CGVectorMake(0.0f, -self.size.height) duration:0.3];
    action.timingMode = SKActionTimingEaseOut;
    [self.gameLayer runAction:action];
}

- (void)removeAllCookieSprites {
    [self.cookiesLayer removeAllChildren];
}

#pragma mark - Private

/**
 *  Converts a column and row number into CGPoint that is relative to the cookieLayer
 *
 *  @param column
 *  @param row
 *
 *  @return the center of the cookie's SKSpriteNode
 */
- (CGPoint)p_pointForColumn:(NSInteger)column row:(NSInteger)row {
    return CGPointMake(column * kTileWidth + kTileWidth / 2, row * kTileHeight + kTileHeight / 2);
}

- (BOOL)p_convertPoint:(CGPoint)point toColumn:(NSInteger *)column row:(NSInteger *)row {
    NSParameterAssert(column);
    NSParameterAssert(row);

    // Is this a valid location within the cookies layer?
    // If yes, calculate the corresponding row and column numbers.
    if (point.x >= 0 && point.x < HRYLevelNumColumns * kTileWidth &&
        point.y >= 0 && point.y < HRYLevelNumRows * kTileHeight) {
        *column = point.x / kTileWidth;
        *row = point.y / kTileHeight;

        return YES;
    }
    else {
        *column = NSNotFound;  // Invalid location
        *row = NSNotFound;

        return NO;
    }
}

- (void)p_trySwapHorizontal:(NSInteger)horzDelta vertical:(NSInteger)vertDelta {
    NSInteger toColumn = self.swipeFromColumn + horzDelta;
    NSInteger toRow = self.swipeFromRow + vertDelta;

    // Outside the 9x9 grid
    if (toColumn < 0 || toColumn >= HRYLevelNumColumns) return;
    if (toRow < 0 || toRow >= HRYLevelNumRows) return;

    HRYCookie *toCookie = [self.level cookieAtColumn:toColumn row:toRow];
    if (!toCookie) return;

    HRYCookie *fromCookie = [self.level cookieAtColumn:self.swipeFromColumn row:self.swipeFromRow];

    if (self.swipeHandler) {
        HRYSwap *swap = [[HRYSwap alloc] init];
        swap.cookieA = fromCookie;
        swap.cookieB = toCookie;

        self.swipeHandler(swap);
    }
}

- (void)p_showSelectionIndicatorForCookie:(HRYCookie *)cookie {
    // If the selection is still visible, then first remove it.
    if (self.selectionSprite.parent) {
        [self.selectionSprite removeFromParent];
    }

    SKTexture *texture = [SKTexture textureWithImageNamed:[cookie highlightedSpriteName]];
    self.selectionSprite.size = texture.size;
    [self.selectionSprite runAction:[SKAction setTexture:texture]];

    [cookie.sprite addChild:self.selectionSprite];
    self.selectionSprite.alpha = 1.0f;
}

- (void)p_hideSelectionIndicator {
    [self.selectionSprite runAction:[SKAction sequence:@[
        [SKAction fadeOutWithDuration:0.3],
        [SKAction removeFromParent]
    ]]];
}

- (void)p_preloadResources {
    // Preload fonts
    [SKLabelNode labelNodeWithFontNamed:@"GillSans-BoldItalic"];

    _swapSound = [SKAction playSoundFileNamed:@"Chomp.wav" waitForCompletion:NO];
    _invalidSwapSound = [SKAction playSoundFileNamed:@"Error.wav" waitForCompletion:NO];
    _matchSound = [SKAction playSoundFileNamed:@"Ka-Ching.wav" waitForCompletion:NO];
    _failingCookieSound = [SKAction playSoundFileNamed:@"Scrape.wav" waitForCompletion:NO];
    _addCookieSound = [SKAction playSoundFileNamed:@"Drip.wav" waitForCompletion:NO];
}

- (void)p_animateScoreForChain:(HRYChain *)chain {
    // Figure out what the midpoint of the chain is.
    HRYCookie *firstCookie = [chain.cookies firstObject];
    HRYCookie *lastCookie = [chain.cookies lastObject];

    CGPoint centerPosition = CGPointMake(
        (firstCookie.sprite.position.x + lastCookie.sprite.position.x) / 2,
        (firstCookie.sprite.position.y + lastCookie.sprite.position.y) / 2 - 8.0f
    );

    // Add a label for the score that slowly floats up.
    SKLabelNode *scoreLabel = [SKLabelNode labelNodeWithFontNamed:@"GillSans-BoldItalic"];
    scoreLabel.fontSize = 16.0f;
    scoreLabel.text = [NSString stringWithFormat:@"%lu", (long)chain.score];
    scoreLabel.position = centerPosition;
    scoreLabel.zPosition = 300.0f;
    [self.cookiesLayer addChild:scoreLabel];

    SKAction *moveAction = [SKAction moveBy:CGVectorMake(0.0f, 3.0f) duration:0.7];
    moveAction.timingMode = SKActionTimingEaseOut;
    [scoreLabel runAction:[SKAction sequence:@[moveAction, [SKAction removeFromParent]]]];
}

@end
