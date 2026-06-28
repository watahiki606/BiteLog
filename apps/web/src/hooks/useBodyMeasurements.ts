import useSWR from 'swr';
import { createClient } from '@/lib/api';

/** API の /body-measurements が返す体組成計測データ（CSV全17列）。 */
export interface BodyMeasurement {
  id: string;
  sourceDate: string | null;
  measuredAt: string;
  measurementDateRaw: string | null;
  measurementTimeRaw: string | null;
  measurementIndex: number | null;
  itemCount: number | null;
  inputMethod: string | null;
  weightKg: number | null;
  bodyFatPercent: number | null;
  muscleMassKg: number | null;
  muscleScore: number | null;
  visceralFatLevel: number | null;
  basalMetabolismKcal: number | null;
  metabolicAge: number | null;
  boneMassKg: number | null;
  bodyWaterPercent: number | null;
  pageUrl: string | null;
}

async function fetchBodyMeasurements(): Promise<BodyMeasurement[]> {
  const res = await createClient().api['body-measurements'].$get();
  if (!res.ok) throw new Error('body-measurements');
  const data = await res.json();
  return data.items as BodyMeasurement[];
}

/** 体組成計測データ一覧（measured_at 降順）。 */
export function useBodyMeasurements(onError?: () => void) {
  return useSWR<BodyMeasurement[]>('body-measurements', fetchBodyMeasurements, {
    revalidateOnFocus: false,
    onError,
  });
}
