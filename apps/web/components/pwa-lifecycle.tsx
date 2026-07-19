"use client";

import { Button } from "@vynlo/ui-web/components/button";
import { RefreshCw, WifiOff } from "lucide-react";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";

interface PwaLifecycleMessages {
  readonly offlineDescription: string;
  readonly offlineTitle: string;
  readonly reloadAction: string;
  readonly updateDescription: string;
  readonly updateTitle: string;
}

interface PwaLifecycleProps {
  readonly messages: PwaLifecycleMessages;
}

function subscribeToConnectivity(onStoreChange: () => void) {
  window.addEventListener("online", onStoreChange);
  window.addEventListener("offline", onStoreChange);

  return () => {
    window.removeEventListener("online", onStoreChange);
    window.removeEventListener("offline", onStoreChange);
  };
}

const getConnectivitySnapshot = () => window.navigator.onLine;
const getServerConnectivitySnapshot = () => true;

export function PwaLifecycle({ messages }: PwaLifecycleProps) {
  const isOnline = useSyncExternalStore(
    subscribeToConnectivity,
    getConnectivitySnapshot,
    getServerConnectivitySnapshot,
  );
  const [waitingWorker, setWaitingWorker] = useState<ServiceWorker | null>(
    null,
  );
  const reloadAfterUpdate = useRef(false);

  useEffect(() => {
    let registration: ServiceWorkerRegistration | undefined;

    const register = async () => {
      if (!("serviceWorker" in window.navigator)) {
        return;
      }

      registration = await window.navigator.serviceWorker.register("/sw.js", {
        scope: "/",
      });

      if (registration.waiting && window.navigator.serviceWorker.controller) {
        setWaitingWorker(registration.waiting);
      }

      registration.addEventListener("updatefound", () => {
        const installingWorker = registration?.installing;
        installingWorker?.addEventListener("statechange", () => {
          if (
            installingWorker.state === "installed" &&
            window.navigator.serviceWorker.controller
          ) {
            setWaitingWorker(installingWorker);
          }
        });
      });
    };

    const checkForUpdate = () => {
      if (document.visibilityState === "visible") {
        void registration?.update();
      }
    };

    const reloadWhenControlled = () => {
      if (reloadAfterUpdate.current) {
        window.location.reload();
      }
    };
    document.addEventListener("visibilitychange", checkForUpdate);
    window.navigator.serviceWorker?.addEventListener(
      "controllerchange",
      reloadWhenControlled,
    );
    void register();

    return () => {
      document.removeEventListener("visibilitychange", checkForUpdate);
      window.navigator.serviceWorker?.removeEventListener(
        "controllerchange",
        reloadWhenControlled,
      );
    };
  }, []);

  const applyUpdate = () => {
    reloadAfterUpdate.current = true;
    waitingWorker?.postMessage({ type: "SKIP_WAITING" });
  };

  if (isOnline && !waitingWorker) {
    return null;
  }

  return (
    <aside aria-live="polite" className="pwa-notice" role="status">
      <div className="pwa-notice__content">
        {isOnline ? (
          <RefreshCw aria-hidden="true" size={20} />
        ) : (
          <WifiOff aria-hidden="true" size={20} />
        )}
        <div>
          <strong>
            {isOnline ? messages.updateTitle : messages.offlineTitle}
          </strong>
          <p>
            {isOnline
              ? messages.updateDescription
              : messages.offlineDescription}
          </p>
        </div>
      </div>
      {waitingWorker ? (
        <Button onClick={applyUpdate} size="sm" variant="secondary">
          {messages.reloadAction}
        </Button>
      ) : null}
    </aside>
  );
}
