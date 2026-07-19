import { describe, expect, it } from "vitest";

import {
  inventoryIntakeMessages,
  vehiclePhotoJobStatusLabel,
  type VehiclePhotoJobStatus,
} from "./inventory-intake-messages";

const statuses = [
  "cancelled",
  "dead_letter",
  "queued",
  "retry_wait",
  "running",
  "succeeded",
] as const satisfies readonly VehiclePhotoJobStatus[];

describe("T-I18N-001 / T-MED-003 vehicle photo job status copy", () => {
  it("maps every durable machine status to complete English and French labels", () => {
    expect(
      statuses.map((status) =>
        vehiclePhotoJobStatusLabel(inventoryIntakeMessages.en, status),
      ),
    ).toEqual([
      "Cancelled",
      "Verification failed",
      "Queued",
      "Waiting to retry",
      "Verification in progress",
      "Verified",
    ]);
    expect(
      statuses.map((status) =>
        vehiclePhotoJobStatusLabel(inventoryIntakeMessages.fr, status),
      ),
    ).toEqual([
      "Annulée",
      "Échec de la vérification",
      "En file d’attente",
      "En attente d’une nouvelle tentative",
      "Vérification en cours",
      "Vérifiée",
    ]);
  });
});
