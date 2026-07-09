import * as React from "react";
import dobermanFrames from "../assets/doberman-frames.png";

const DEFAULT_IDLE_TIMEOUT_MS = 300000;
const DEFAULT_PROBABILITY = 0.2;
const DEFAULT_NAVBAR_SELECTOR = "[data-doberman-navbar], .MuiAppBar-root";
const DEFAULT_PLACEMENT = "navbar";
const DEFAULT_BOTTOM_OFFSET = 12;
const DEFAULT_SCALE = 3;
const DEFAULT_Z_INDEX = 2147483000;
const DEFAULT_DEBUG_RESTART_DELAY_MS = 250;
const DEFAULT_CONSOLE_COMMAND_NAME = "showDobermanEasterEgg";
const DEFAULT_SIT_HOLD_MS = 7000;

const FRAME_WIDTH = 40;
const FRAME_HEIGHT = 30;
const SHEET_COLUMNS = 4;
const SHEET_ROWS = 6;
const FRAME_DURATION_MS = 100;
const ACTIVITY_THROTTLE_MS = 1000;

const makeFrame = (row, column) => ({
  row: row - 1,
  column: column - 1,
});

const frame = (frameId) => {
  const [row, column] = String(frameId).split(".").map(Number);

  if (!Number.isFinite(row) || !Number.isFinite(column)) {
    throw new Error(`Invalid Doberman frame id: ${frameId}`);
  }

  return makeFrame(row, column);
};

const frames = (...frameIds) => frameIds.map(frame);
const reverseFrames = (sequence) => [...sequence].reverse();

const SIT_TRANSITION_FRAMES = frames("3.1");
const LAY_TRANSITION_FRAMES = frames("3.4", "4.1", "4.2");

const DOBERMAN_ANIMATIONS = {
  walk: {
    frames: frames("1.1", "1.2", "1.3", "1.4", "2.1", "2.2", "2.3", "2.4"),
    loop: true,
  },
  sitTransition: {
    frames: SIT_TRANSITION_FRAMES,
    loop: false,
  },
  sitHold: {
    frames: frames("3.2"),
    holdMs: DEFAULT_SIT_HOLD_MS,
  },
  sitLookAround: {
    frames: frames("3.3"),
    holdMs: DEFAULT_SIT_HOLD_MS,
  },
  standTransition: {
    frames: reverseFrames(SIT_TRANSITION_FRAMES),
    loop: false,
  },
  layTransition: {
    frames: LAY_TRANSITION_FRAMES,
    loop: false,
  },
  layHold: {
    frames: frames("4.2"),
    holdMs: DEFAULT_SIT_HOLD_MS,
  },
  layLookAround: {
    frames: frames("4.3"),
    holdMs: DEFAULT_SIT_HOLD_MS,
  },
  lay: {
    frames: frames("4.4"),
    holdMs: DEFAULT_SIT_HOLD_MS,
  },
  sleepLoop: {
    frames: frames("5.1", "5.2", "5.3", "5.4", "6.1", "6.2", "6.3", "6.4"),
    loop: true,
  },
  standFromLayTransition: {
    frames: reverseFrames(LAY_TRANSITION_FRAMES),
    loop: false,
  },
};

// const DEFAULT_DOBERMAN_TIMELINE = [
//   { action: "walk", moveTo: "center" },
//   { action: "sitTransition" },
//   { action: "sitHold" },
//   { action: "standTransition" },
//   { action: "walk", moveTo: "exit" },
// ];
const DEFAULT_DOBERMAN_TIMELINE = [
  { action: "walk", moveTo: "25%" },
  { action: "layTransition" },
  { action: "layHold" },
  { action: "layLookAround" },
  { action: "lay" },
  { action: "sleepLoop", holdMs: 10000 },
  { action: "standFromLayTransition" },
  { action: "walk", moveTo: "75%" },
  { action: "sitTransition" },
  { action: "sitHold" },
  { action: "sitLookAround" },
  { action: "sitTransition" },
  { action: "walk", moveTo: "exit" },
];

const DEFAULT_FRAME = frame("1.1");

const clearTimer = (timerRef) => {
  if (timerRef.current !== null) {
    window.clearTimeout(timerRef.current);
    timerRef.current = null;
  }
};

const getTimestamp = (timestamp) =>
  timestamp ? new Date(timestamp).toISOString() : null;

const getMovementDuration = (distance) =>
  Math.round(Math.min(9000, Math.max(3500, Math.abs(distance) * 7)));

const getSpriteStyle = ({ frame: spriteFrame, scale, extraStyle }) => ({
  width: FRAME_WIDTH * scale,
  height: FRAME_HEIGHT * scale,
  backgroundImage: `url(${dobermanFrames})`,
  backgroundPosition: `${-spriteFrame.column * FRAME_WIDTH * scale}px ${
    -spriteFrame.row * FRAME_HEIGHT * scale
  }px`,
  backgroundRepeat: "no-repeat",
  backgroundSize: `${SHEET_COLUMNS * FRAME_WIDTH * scale}px ${
    SHEET_ROWS * FRAME_HEIGHT * scale
  }px`,
  imageRendering: "pixelated",
  ...extraStyle,
});

const getRunLayout = ({ bottomOffset, navbarSelector, placement, scale }) => {
  const spriteWidth = FRAME_WIDTH * scale;
  const spriteHeight = FRAME_HEIGHT * scale;
  const useBottomPlacement = placement === "bottom";
  const navbarElement =
    !useBottomPlacement && typeof document !== "undefined"
      ? document.querySelector(navbarSelector)
      : null;
  const navbarRect = navbarElement?.getBoundingClientRect();
  const viewportWidth =
    typeof window === "undefined" ? 1280 : window.innerWidth;
  const viewportHeight =
    typeof window === "undefined" ? 720 : window.innerHeight;
  const navbarLeft = navbarRect?.left ?? 0;
  const navbarBottom = navbarRect?.bottom ?? 72;
  const startX = Math.round(
    useBottomPlacement ? -spriteWidth - 12 : navbarLeft - spriteWidth - 12,
  );
  const centerX = Math.round(viewportWidth / 2 - spriteWidth / 2);
  const exitX = Math.round(viewportWidth + 24);
  const top = Math.round(
    useBottomPlacement
      ? Math.max(0, viewportHeight - spriteHeight - bottomOffset)
      : navbarBottom - spriteHeight + 2,
  );

  return {
    centerX,
    exitX,
    spriteWidth,
    startX,
    top,
    viewportWidth,
  };
};

const parsePercent = (value) =>
  typeof value === "string"
    ? Number(value.trim().replace(/%$/, ""))
    : Number(value);

const clampPercent = (value) =>
  Math.min(100, Math.max(0, parsePercent(value) || 0));

const getPercentTargetX = (run, percent) =>
  Math.round(
    (run.viewportWidth * clampPercent(percent)) / 100 - run.spriteWidth / 2,
  );

const getTargetX = (run, step) => {
  const { moveTo } = step;

  if (step.moveToPercent != null) {
    return getPercentTargetX(run, step.moveToPercent);
  }

  if (typeof moveTo === "number") {
    return getPercentTargetX(run, moveTo);
  }

  if (typeof moveTo === "string" && moveTo.trim().endsWith("%")) {
    return getPercentTargetX(run, moveTo);
  }

  if (moveTo === "center") {
    return run.centerX;
  }

  if (moveTo === "exit") {
    return run.exitX;
  }

  if (moveTo === "start") {
    return run.startX;
  }

  return run.x;
};

const hasMovementTarget = (step) =>
  Boolean(step.moveTo) ||
  step.moveToPercent != null ||
  typeof step.moveTo === "number";

const getStepHoldMs = ({ actionName, animation, safeSitHoldMs, step }) => {
  if (step.holdMs != null) {
    return Math.max(0, Number(step.holdMs) || 0);
  }

  if (actionName === "sitHold" && safeSitHoldMs !== null) {
    return safeSitHoldMs;
  }

  if (animation.holdMs != null) {
    return Math.max(0, Number(animation.holdMs) || 0);
  }

  return null;
};

const getFrameId = (spriteFrame) =>
  `${spriteFrame.row + 1}.${spriteFrame.column + 1}`;

const getFrameIds = (animationFrames = []) =>
  animationFrames.map(getFrameId).join(" -> ");

const getDebugMs = (ms) => ({
  ms,
  seconds: Number((ms / 1000).toFixed(2)),
  minutes: Number((ms / 60000).toFixed(2)),
});

const getTimelineDebugRows = ({
  resolvedAnimations,
  resolvedTimeline,
  safeSitHoldMs,
}) =>
  resolvedTimeline.map((step, index) => {
    const animation = resolvedAnimations[step.action];
    const holdMs = animation
      ? getStepHoldMs({
          actionName: step.action,
          animation,
          safeSitHoldMs,
          step,
        })
      : null;
    const moveTo =
      step.moveToPercent != null ? `${step.moveToPercent}%` : step.moveTo || "";

    return {
      step: index + 1,
      action: step.action,
      found: Boolean(animation),
      frames: getFrameIds(animation?.frames || []),
      loop: Boolean(animation?.loop),
      holdMs: holdMs ?? "",
      moveTo,
      durationMs: step.durationMs ?? "",
      frameDurationMs: animation?.frameDurationMs ?? FRAME_DURATION_MS,
    };
  });

const checkDobermanAssetLoad = ({ logs = false } = {}) =>
  new Promise((resolve) => {
    const startedAt =
      typeof performance !== "undefined" ? performance.now() : Date.now();
    const image = new Image();
    const expectedWidth = SHEET_COLUMNS * FRAME_WIDTH;
    const expectedHeight = SHEET_ROWS * FRAME_HEIGHT;
    const getElapsedMs = () => {
      const now =
        typeof performance !== "undefined" ? performance.now() : Date.now();
      return Math.round(now - startedAt);
    };

    image.onload = () => {
      const result = {
        ok: true,
        src: dobermanFrames,
        naturalWidth: image.naturalWidth,
        naturalHeight: image.naturalHeight,
        expectedWidth,
        expectedHeight,
        expectedSizeMatches:
          image.naturalWidth === expectedWidth &&
          image.naturalHeight === expectedHeight,
        elapsedMs: getElapsedMs(),
      };

      if (logs) {
        console.info("[DobermanEasterEgg] sprite asset loaded", result);
      }

      resolve(result);
    };

    image.onerror = () => {
      const result = {
        ok: false,
        src: dobermanFrames,
        expectedWidth,
        expectedHeight,
        error: "sprite-image-load-error",
        elapsedMs: getElapsedMs(),
      };

      if (logs) {
        console.error(
          "[DobermanEasterEgg] sprite asset failed to load",
          result,
        );
      }

      resolve(result);
    };

    image.src = dobermanFrames;
  });

const logDobermanRunDebug = ({
  commandOptions,
  isDebugAlwaysOn,
  layout,
  resolvedAnimations,
  resolvedTimeline,
  safeBottomOffset,
  safeDebugRestartDelayMs,
  safeIdleTimeoutMs,
  safePlacement,
  safeProbability,
  safeScale,
  safeSitHoldMs,
  source,
  zIndex,
}) => {
  const nextIdleDelayMs = isDebugAlwaysOn
    ? safeDebugRestartDelayMs
    : safeIdleTimeoutMs;

  console.groupCollapsed("[DobermanEasterEgg] forced run debug");
  console.info("[DobermanEasterEgg] command", {
    source,
    options: commandOptions,
    forcedRunStartsImmediately: source === "console",
  });
  console.info("[DobermanEasterEgg] idle timing", {
    idleTimeout: getDebugMs(safeIdleTimeoutMs),
    debugAlwaysOn: isDebugAlwaysOn,
    debugRestartDelay: getDebugMs(safeDebugRestartDelayMs),
    nextEligibleIdleRunDelay: getDebugMs(nextIdleDelayMs),
    probability: safeProbability,
  });
  console.info("[DobermanEasterEgg] sprite asset", {
    src: dobermanFrames,
    expectedWidth: SHEET_COLUMNS * FRAME_WIDTH,
    expectedHeight: SHEET_ROWS * FRAME_HEIGHT,
    frameWidth: FRAME_WIDTH,
    frameHeight: FRAME_HEIGHT,
    sheetColumns: SHEET_COLUMNS,
    sheetRows: SHEET_ROWS,
  });
  console.info("[DobermanEasterEgg] placement", {
    placement: safePlacement,
    bottomOffset: safeBottomOffset,
    scale: safeScale,
    zIndex,
    layout,
  });
  console.table(
    getTimelineDebugRows({
      resolvedAnimations,
      resolvedTimeline,
      safeSitHoldMs,
    }),
  );
  console.groupEnd();
};

const logDobermanStepDebug = ({
  animation,
  currentRun,
  holdMs,
  movementMs,
  step,
  targetX,
}) => {
  console.info("[DobermanEasterEgg] timeline step", {
    runId: currentRun.id,
    step: currentRun.stepIndex + 1,
    action: step.action,
    found: Boolean(animation.frames),
    frames: getFrameIds(animation.frames || []),
    loop: Boolean(animation.loop),
    holdMs: holdMs ?? "",
    movementMs: movementMs ?? "",
    fromX: currentRun.x,
    targetX: targetX ?? "",
  });
};

function SpriteAnimator({
  animationKey,
  className,
  frameDurationMs = FRAME_DURATION_MS,
  frames: animationFrames,
  isLooping = false,
  onComplete,
  scale,
  style,
}) {
  const [frameIndex, setFrameIndex] = React.useState(0);
  const onCompleteRef = React.useRef(onComplete);

  React.useEffect(() => {
    onCompleteRef.current = onComplete;
  }, [onComplete]);

  React.useEffect(() => {
    setFrameIndex(0);

    if (animationFrames.length <= 1) {
      if (isLooping || !onCompleteRef.current) {
        return undefined;
      }

      const completeTimerId = window.setTimeout(() => {
        onCompleteRef.current?.();
      }, frameDurationMs);

      return () => window.clearTimeout(completeTimerId);
    }

    let nextFrameIndex = 0;
    let completeTimerId = null;
    const frameTimerId = window.setInterval(() => {
      nextFrameIndex += 1;

      if (nextFrameIndex >= animationFrames.length) {
        if (isLooping) {
          nextFrameIndex = 0;
          setFrameIndex(0);
        }
        return;
      }

      setFrameIndex(nextFrameIndex);

      if (!isLooping && nextFrameIndex === animationFrames.length - 1) {
        window.clearInterval(frameTimerId);
        completeTimerId = window.setTimeout(() => {
          onCompleteRef.current?.();
        }, frameDurationMs);
      }
    }, frameDurationMs);

    return () => {
      window.clearInterval(frameTimerId);
      if (completeTimerId !== null) {
        window.clearTimeout(completeTimerId);
      }
    };
  }, [animationFrames, animationKey, frameDurationMs, isLooping]);

  const spriteFrame =
    animationFrames[frameIndex] ?? animationFrames[0] ?? DEFAULT_FRAME;

  return (
    <div
      className={className}
      style={getSpriteStyle({
        frame: spriteFrame,
        scale,
        extraStyle: {
          position: "absolute",
          inset: 0,
          ...style,
        },
      })}
    />
  );
}

export default function DobermanEasterEgg({
  animations = DOBERMAN_ANIMATIONS,
  bottomOffset = DEFAULT_BOTTOM_OFFSET,
  consoleCommandName = DEFAULT_CONSOLE_COMMAND_NAME,
  debugAlwaysOn = false,
  debugRestartDelayMs = DEFAULT_DEBUG_RESTART_DELAY_MS,
  enableConsoleCommand = true,
  idleTimeoutMs = DEFAULT_IDLE_TIMEOUT_MS,
  probability = DEFAULT_PROBABILITY,
  navbarSelector = DEFAULT_NAVBAR_SELECTOR,
  placement = DEFAULT_PLACEMENT,
  scale = DEFAULT_SCALE,
  sitHoldMs,
  timeline = DEFAULT_DOBERMAN_TIMELINE,
  zIndex = DEFAULT_Z_INDEX,
}) {
  const [run, setRun] = React.useState(null);
  const idleTimerRef = React.useRef(null);
  const triggerIdleRef = React.useRef(() => {});
  const runRef = React.useRef(null);
  const movementStartTimerRef = React.useRef(null);
  const stepCompleteTimerRef = React.useRef(null);
  const holdTimerRef = React.useRef(null);
  const idleDebugLogsRef = React.useRef(false);
  const idleStateRef = React.useRef({
    activityResetCount: 0,
    idleTimerDueAt: null,
    idleTimerFiredAt: null,
    idleTimerReason: null,
    idleTimerStartedAt: null,
    lastActivityAt: null,
    lastActivityType: null,
    lastIdleTriggerAt: null,
    lastProbabilityRoll: null,
    lastProbabilitySkippedAt: null,
    mountedAt: Date.now(),
  });

  const safeBottomOffset = Math.max(0, Number(bottomOffset) || 0);
  const isDebugAlwaysOn = Boolean(debugAlwaysOn);
  const safeDebugRestartDelayMs = Math.max(0, Number(debugRestartDelayMs) || 0);
  const safeIdleTimeoutMs = Math.max(0, Number(idleTimeoutMs) || 0);
  const safeProbability = Math.min(1, Math.max(0, Number(probability) || 0));
  const safePlacement = placement === "bottom" ? "bottom" : DEFAULT_PLACEMENT;
  const safeScale = Math.max(0.1, Number(scale) || DEFAULT_SCALE);
  const safeSitHoldMs =
    sitHoldMs == null ? null : Math.max(0, Number(sitHoldMs) || 0);
  const resolvedAnimations = animations || DOBERMAN_ANIMATIONS;
  const resolvedTimeline =
    Array.isArray(timeline) && timeline.length > 0
      ? timeline
      : DEFAULT_DOBERMAN_TIMELINE;

  const setConcreteRun = React.useCallback((nextRun) => {
    runRef.current = nextRun;
    setRun(nextRun);
  }, []);

  const clearStepTimers = React.useCallback(() => {
    clearTimer(movementStartTimerRef);
    clearTimer(stepCompleteTimerRef);
    clearTimer(holdTimerRef);
  }, []);

  const clearRunTimers = React.useCallback(() => {
    clearStepTimers();
  }, [clearStepTimers]);

  const scheduleIdleTimer = React.useCallback(
    (reason = "schedule") => {
      clearTimer(idleTimerRef);

      if (runRef.current) {
        if (idleDebugLogsRef.current) {
          console.info(
            "[DobermanEasterEgg] idle timer not scheduled during run",
            {
              reason,
              runId: runRef.current.id,
            },
          );
        }
        return;
      }

      const nextTimeoutMs = isDebugAlwaysOn
        ? safeDebugRestartDelayMs
        : safeIdleTimeoutMs;
      const now = Date.now();
      idleStateRef.current.idleTimerStartedAt = now;
      idleStateRef.current.idleTimerDueAt = now + nextTimeoutMs;
      idleStateRef.current.idleTimerReason = reason;

      if (idleDebugLogsRef.current) {
        console.info("[DobermanEasterEgg] idle timer scheduled", {
          reason,
          timeoutMs: nextTimeoutMs,
          dueAt: getTimestamp(idleStateRef.current.idleTimerDueAt),
        });
      }

      idleTimerRef.current = window.setTimeout(() => {
        idleStateRef.current.idleTimerFiredAt = Date.now();
        idleStateRef.current.idleTimerDueAt = null;
        idleTimerRef.current = null;

        if (idleDebugLogsRef.current) {
          console.info("[DobermanEasterEgg] idle timer fired", {
            firedAt: getTimestamp(idleStateRef.current.idleTimerFiredAt),
            reason,
          });
        }

        triggerIdleRef.current();
      }, nextTimeoutMs);
    },
    [isDebugAlwaysOn, safeDebugRestartDelayMs, safeIdleTimeoutMs],
  );

  const getDebugStatus = React.useCallback(() => {
    const now = Date.now();
    const idleState = idleStateRef.current;
    const currentRun = runRef.current;
    const nextEligibleIdleRunDelayMs = isDebugAlwaysOn
      ? safeDebugRestartDelayMs
      : safeIdleTimeoutMs;

    return {
      assetUrl: dobermanFrames,
      debugAlwaysOn: isDebugAlwaysOn,
      idle: {
        activityResetCount: idleState.activityResetCount,
        debugLogsEnabled: idleDebugLogsRef.current,
        idleTimeoutMs: safeIdleTimeoutMs,
        lastActivityAt: getTimestamp(idleState.lastActivityAt),
        lastActivityType: idleState.lastActivityType,
        lastIdleTriggerAt: getTimestamp(idleState.lastIdleTriggerAt),
        lastProbabilityRoll: idleState.lastProbabilityRoll,
        lastProbabilitySkippedAt: getTimestamp(
          idleState.lastProbabilitySkippedAt,
        ),
        nextEligibleIdleRunDelayMs,
        timerActive: idleTimerRef.current !== null,
        timerDueAt: getTimestamp(idleState.idleTimerDueAt),
        timerFiredAt: getTimestamp(idleState.idleTimerFiredAt),
        timerReason: idleState.idleTimerReason,
        timerRemainingMs: idleState.idleTimerDueAt
          ? Math.max(0, idleState.idleTimerDueAt - now)
          : null,
        timerStartedAt: getTimestamp(idleState.idleTimerStartedAt),
      },
      mountedAt: getTimestamp(idleState.mountedAt),
      probability: safeProbability,
      run: currentRun
        ? {
            elapsedMs: now - currentRun.startedAt,
            id: currentRun.id,
            source: currentRun.source,
            stepIndex: currentRun.stepIndex,
          }
        : null,
      visible: Boolean(currentRun),
    };
  }, [
    isDebugAlwaysOn,
    safeDebugRestartDelayMs,
    safeIdleTimeoutMs,
    safeProbability,
  ]);

  const finishRun = React.useCallback(
    (runId) => {
      const currentRun = runRef.current;

      if (runId && currentRun?.id !== runId) {
        return;
      }

      if (currentRun?.debugLogs) {
        console.info("[DobermanEasterEgg] run finished", {
          runId: currentRun.id,
          source: currentRun.source,
          completedSteps: currentRun.stepIndex + 1,
          elapsedMs: Date.now() - currentRun.startedAt,
        });
      }

      clearRunTimers();
      runRef.current = null;
      setRun(null);
      scheduleIdleTimer("run-finished");
    },
    [clearRunTimers, scheduleIdleTimer],
  );

  const advanceTimeline = React.useCallback(
    (runId, stepIndex) => {
      const currentRun = runRef.current;

      if (
        !currentRun ||
        currentRun.id !== runId ||
        currentRun.stepIndex !== stepIndex
      ) {
        return;
      }

      const nextStepIndex = stepIndex + 1;

      if (currentRun.debugLogs) {
        console.info("[DobermanEasterEgg] step complete", {
          runId,
          completedStep: stepIndex + 1,
          nextStep: nextStepIndex + 1,
        });
      }

      if (nextStepIndex >= resolvedTimeline.length) {
        finishRun(runId);
        return;
      }

      clearStepTimers();
      setConcreteRun({
        ...currentRun,
        movementMs: 0,
        stepIndex: nextStepIndex,
      });
    },
    [clearStepTimers, finishRun, resolvedTimeline.length, setConcreteRun],
  );

  const startRun = React.useCallback(
    (options = {}) => {
      const runOptions =
        options && typeof options === "object" && !Array.isArray(options)
          ? options
          : {};
      const debugLogs = Boolean(runOptions.debugLogs);
      const source = runOptions.source || "idle";

      clearTimer(idleTimerRef);
      clearRunTimers();

      const layout = getRunLayout({
        bottomOffset: safeBottomOffset,
        navbarSelector,
        placement: safePlacement,
        scale: safeScale,
      });
      const runId = window.crypto?.randomUUID?.() ?? String(Date.now());
      const assetCheck = debugLogs
        ? checkDobermanAssetLoad({ logs: true })
        : null;

      if (debugLogs) {
        logDobermanRunDebug({
          commandOptions: runOptions.commandOptions || {},
          isDebugAlwaysOn,
          layout,
          resolvedAnimations,
          resolvedTimeline,
          safeBottomOffset,
          safeDebugRestartDelayMs,
          safeIdleTimeoutMs,
          safePlacement,
          safeProbability,
          safeScale,
          safeSitHoldMs,
          source,
          zIndex,
        });
      }

      const nextRun = {
        ...layout,
        debugLogs,
        id: runId,
        movementMs: 0,
        source,
        startedAt: Date.now(),
        stepIndex: 0,
        x: layout.startX,
      };

      setConcreteRun(nextRun);

      return {
        assetCheck,
        layout,
        runId,
      };
    },
    [
      clearRunTimers,
      isDebugAlwaysOn,
      navbarSelector,
      resolvedAnimations,
      resolvedTimeline,
      safeBottomOffset,
      safeDebugRestartDelayMs,
      safeIdleTimeoutMs,
      safePlacement,
      safeProbability,
      safeScale,
      safeSitHoldMs,
      setConcreteRun,
      zIndex,
    ],
  );

  React.useEffect(() => {
    if (!enableConsoleCommand) {
      return undefined;
    }

    const safeConsoleCommandName = String(
      consoleCommandName || DEFAULT_CONSOLE_COMMAND_NAME,
    ).trim();

    if (!safeConsoleCommandName) {
      return undefined;
    }

    const hadPreviousCommand = Object.prototype.hasOwnProperty.call(
      window,
      safeConsoleCommandName,
    );
    const previousCommand = window[safeConsoleCommandName];

    const triggerDoberman = (options = {}) => {
      const commandOptions =
        options && typeof options === "object" && !Array.isArray(options)
          ? options
          : {};
      const hasIdleLogsOption = Object.prototype.hasOwnProperty.call(
        commandOptions,
        "idleLogs",
      );
      const shouldReturnStatus = Boolean(commandOptions.status);
      const shouldResetIdleTimer = Boolean(commandOptions.resetIdleTimer);
      const shouldRestart = Boolean(commandOptions.restart);
      const shouldLog = Boolean(commandOptions.logs);

      if (hasIdleLogsOption) {
        idleDebugLogsRef.current = Boolean(commandOptions.idleLogs);
      }

      if (shouldResetIdleTimer) {
        scheduleIdleTimer("console-reset");
      }

      if (
        shouldReturnStatus ||
        shouldResetIdleTimer ||
        (hasIdleLogsOption && !shouldRestart)
      ) {
        const assetCheck = shouldLog
          ? checkDobermanAssetLoad({ logs: true })
          : null;
        const status = getDebugStatus();
        const response = {
          assetCheck,
          ok: true,
          status: "debug-status",
          ...status,
        };

        if (shouldLog || hasIdleLogsOption) {
          console.info("[DobermanEasterEgg] debug status", response);
        }

        return response;
      }

      if (runRef.current && !shouldRestart) {
        const response = {
          ok: false,
          status: "already-running",
          restartCommand: `${safeConsoleCommandName}({ restart: true })`,
        };

        if (shouldLog) {
          response.assetCheck = checkDobermanAssetLoad({ logs: true });
          console.info("[DobermanEasterEgg] command skipped", {
            ...response,
            currentRun: runRef.current,
          });
        }

        return response;
      }

      const startResult = startRun({
        commandOptions,
        debugLogs: shouldLog,
        source: "console",
      });

      const response = {
        assetCheck: startResult?.assetCheck || null,
        assetUrl: dobermanFrames,
        idleTimeoutMs: safeIdleTimeoutMs,
        nextEligibleIdleRunDelayMs: isDebugAlwaysOn
          ? safeDebugRestartDelayMs
          : safeIdleTimeoutMs,
        ok: true,
        runId: startResult?.runId,
        status: shouldRestart ? "restarted" : "started",
      };

      if (shouldLog) {
        console.info("[DobermanEasterEgg] command result", response);
      }

      return response;
    };

    window[safeConsoleCommandName] = triggerDoberman;

    return () => {
      if (window[safeConsoleCommandName] !== triggerDoberman) {
        return;
      }

      if (hadPreviousCommand) {
        window[safeConsoleCommandName] = previousCommand;
        return;
      }

      delete window[safeConsoleCommandName];
    };
  }, [
    consoleCommandName,
    enableConsoleCommand,
    getDebugStatus,
    isDebugAlwaysOn,
    safeDebugRestartDelayMs,
    safeIdleTimeoutMs,
    scheduleIdleTimer,
    startRun,
  ]);

  React.useEffect(() => {
    triggerIdleRef.current = () => {
      idleStateRef.current.lastIdleTriggerAt = Date.now();

      if (runRef.current) {
        if (idleDebugLogsRef.current) {
          console.info("[DobermanEasterEgg] idle trigger ignored during run", {
            runId: runRef.current.id,
          });
        }
        return;
      }

      const probabilityRoll = Math.random();
      idleStateRef.current.lastProbabilityRoll = probabilityRoll;

      if (!isDebugAlwaysOn && probabilityRoll > safeProbability) {
        idleStateRef.current.lastProbabilitySkippedAt = Date.now();

        if (idleDebugLogsRef.current) {
          console.info(
            "[DobermanEasterEgg] idle trigger skipped by probability",
            {
              probability: safeProbability,
              roll: probabilityRoll,
            },
          );
        }

        scheduleIdleTimer("probability-skip");
        return;
      }

      if (idleDebugLogsRef.current) {
        console.info("[DobermanEasterEgg] idle trigger starting run", {
          debugAlwaysOn: isDebugAlwaysOn,
          probability: safeProbability,
          roll: probabilityRoll,
        });
      }

      startRun({
        debugLogs: idleDebugLogsRef.current,
        source: "idle",
      });
    };
  }, [isDebugAlwaysOn, safeProbability, scheduleIdleTimer, startRun]);

  React.useEffect(() => {
    if (isDebugAlwaysOn) {
      scheduleIdleTimer("debug-always-on");

      return () => {
        clearTimer(idleTimerRef);
      };
    }

    let lastActivityAt = 0;
    const listenerOptions = { capture: true, passive: true };

    const handleActivity = (event) => {
      if (runRef.current) {
        return;
      }

      const now = Date.now();
      if (now - lastActivityAt < ACTIVITY_THROTTLE_MS) {
        return;
      }

      lastActivityAt = now;
      idleStateRef.current.activityResetCount += 1;
      idleStateRef.current.lastActivityAt = now;
      idleStateRef.current.lastActivityType = event.type;

      if (idleDebugLogsRef.current) {
        console.info("[DobermanEasterEgg] activity reset idle timer", {
          activityResetCount: idleStateRef.current.activityResetCount,
          eventType: event.type,
          nextTimeoutMs: isDebugAlwaysOn
            ? safeDebugRestartDelayMs
            : safeIdleTimeoutMs,
        });
      }

      scheduleIdleTimer(`activity:${event.type}`);
    };

    window.addEventListener("mousemove", handleActivity, listenerOptions);
    window.addEventListener("click", handleActivity, listenerOptions);
    window.addEventListener("keydown", handleActivity, listenerOptions);
    window.addEventListener("scroll", handleActivity, listenerOptions);
    scheduleIdleTimer("mount");

    return () => {
      window.removeEventListener("mousemove", handleActivity, listenerOptions);
      window.removeEventListener("click", handleActivity, listenerOptions);
      window.removeEventListener("keydown", handleActivity, listenerOptions);
      window.removeEventListener("scroll", handleActivity, listenerOptions);
      clearTimer(idleTimerRef);
    };
  }, [
    isDebugAlwaysOn,
    safeDebugRestartDelayMs,
    safeIdleTimeoutMs,
    scheduleIdleTimer,
  ]);

  React.useEffect(() => {
    const currentRun = runRef.current;

    if (!currentRun) {
      return undefined;
    }

    const step = resolvedTimeline[currentRun.stepIndex];

    if (!step) {
      finishRun(currentRun.id);
      return undefined;
    }

    const animation = resolvedAnimations[step.action] || {};
    const holdMs = getStepHoldMs({
      actionName: step.action,
      animation,
      safeSitHoldMs,
      step,
    });

    clearStepTimers();

    if (hasMovementTarget(step)) {
      const targetX = getTargetX(currentRun, step);
      const movementMs =
        step.durationMs != null
          ? Math.max(0, Number(step.durationMs) || 0)
          : getMovementDuration(targetX - currentRun.x);

      if (currentRun.debugLogs) {
        logDobermanStepDebug({
          animation,
          currentRun,
          holdMs,
          movementMs,
          step,
          targetX,
        });
      }

      movementStartTimerRef.current = window.setTimeout(() => {
        const latestRun = runRef.current;

        if (
          !latestRun ||
          latestRun.id !== currentRun.id ||
          latestRun.stepIndex !== currentRun.stepIndex
        ) {
          return;
        }

        setConcreteRun({
          ...latestRun,
          movementMs,
          x: targetX,
        });

        stepCompleteTimerRef.current = window.setTimeout(() => {
          advanceTimeline(currentRun.id, currentRun.stepIndex);
        }, movementMs);
      }, 50);

      return () => {
        clearStepTimers();
      };
    }

    if (holdMs !== null) {
      if (currentRun.debugLogs) {
        logDobermanStepDebug({
          animation,
          currentRun,
          holdMs,
          step,
        });
      }

      holdTimerRef.current = window.setTimeout(() => {
        advanceTimeline(currentRun.id, currentRun.stepIndex);
      }, holdMs);

      return () => {
        clearStepTimers();
      };
    }

    if (currentRun.debugLogs) {
      logDobermanStepDebug({
        animation,
        currentRun,
        holdMs,
        step,
      });
    }

    return undefined;
  }, [
    advanceTimeline,
    clearStepTimers,
    finishRun,
    resolvedAnimations,
    resolvedTimeline,
    run?.id,
    run?.stepIndex,
    safeSitHoldMs,
    setConcreteRun,
  ]);

  React.useEffect(() => {
    if (!run) {
      return undefined;
    }

    const handleResize = () => {
      const currentRun = runRef.current;

      if (!currentRun) {
        return;
      }

      const layout = getRunLayout({
        bottomOffset: safeBottomOffset,
        navbarSelector,
        placement: safePlacement,
        scale: safeScale,
      });
      const step = resolvedTimeline[currentRun.stepIndex];
      const shouldStayCentered = !step || !hasMovementTarget(step);
      const nextRun = {
        ...currentRun,
        ...layout,
        x: shouldStayCentered ? layout.centerX : currentRun.x,
      };

      setConcreteRun(nextRun);
    };

    window.addEventListener("resize", handleResize, { passive: true });

    return () => {
      window.removeEventListener("resize", handleResize);
    };
  }, [
    navbarSelector,
    resolvedTimeline,
    run,
    safeBottomOffset,
    safePlacement,
    safeScale,
    setConcreteRun,
  ]);

  React.useEffect(
    () => () => {
      clearTimer(idleTimerRef);
      clearRunTimers();
    },
    [clearRunTimers],
  );

  const handleAnimationComplete = React.useCallback(() => {
    const currentRun = runRef.current;

    if (!currentRun) {
      return;
    }

    if (currentRun.debugLogs) {
      console.info("[DobermanEasterEgg] sprite animation complete", {
        runId: currentRun.id,
        step: currentRun.stepIndex + 1,
      });
    }

    advanceTimeline(currentRun.id, currentRun.stepIndex);
  }, [advanceTimeline]);

  if (!run) {
    return null;
  }

  const currentStep = resolvedTimeline[run.stepIndex] || {};
  const currentAnimation = resolvedAnimations[currentStep.action] || {};
  const currentFrames = currentAnimation.frames || [DEFAULT_FRAME];
  const hasHold = getStepHoldMs({
    actionName: currentStep.action,
    animation: currentAnimation,
    safeSitHoldMs,
    step: currentStep,
  });
  const isLooping = Boolean(currentAnimation.loop);
  const shouldCompleteFromSprite = !isLooping && hasHold === null;
  const animationKey = `${run.id}-${run.stepIndex}-${currentStep.action || "none"}`;

  return (
    <div
      aria-hidden="true"
      className="doberman-easter-egg"
      style={{
        height: FRAME_HEIGHT * safeScale,
        left: 0,
        overflow: "visible",
        pointerEvents: "none",
        position: "fixed",
        top: run.top,
        width: 0,
        zIndex,
      }}
    >
      <style>
        {`
          .doberman-easter-egg,
          .doberman-easter-egg * {
            box-sizing: border-box;
            pointer-events: none;
          }

          .doberman-easter-egg__traveler {
            will-change: transform;
          }

          .doberman-easter-egg__sprite--walking {
            animation: doberman-walk-bob 360ms steps(2, end) infinite;
          }

          @keyframes doberman-walk-bob {
            0%,
            100% {
              margin-top: 0;
            }

            50% {
              margin-top: -1px;
            }
          }
        `}
      </style>
      <div
        className="doberman-easter-egg__traveler"
        style={{
          height: FRAME_HEIGHT * safeScale,
          position: "relative",
          transform: `translate3d(${run.x}px, 0, 0)`,
          transition:
            run.movementMs > 0
              ? `transform ${run.movementMs}ms linear`
              : "none",
          width: FRAME_WIDTH * safeScale,
        }}
      >
        <SpriteAnimator
          animationKey={animationKey}
          className={
            currentStep.action === "walk"
              ? "doberman-easter-egg__sprite--walking"
              : undefined
          }
          frameDurationMs={currentAnimation.frameDurationMs}
          frames={currentFrames}
          isLooping={isLooping}
          onComplete={
            shouldCompleteFromSprite ? handleAnimationComplete : undefined
          }
          scale={safeScale}
        />
      </div>
    </div>
  );
}
