'use client';

import { useEffect, useRef } from 'react';

type Props = {
  payload: Record<string, string | number>;
};

export function AttendanceQrDisplay({ payload }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const encoded = JSON.stringify(payload);

  useEffect(() => {
    let cancelled = false;
    void import('qrcode').then((QRCode) => {
      if (cancelled || !canvasRef.current) return;
      void QRCode.toCanvas(canvasRef.current, encoded, {
        width: 360,
        margin: 2,
        errorCorrectionLevel: 'M',
      });
    });
    return () => {
      cancelled = true;
    };
  }, [encoded]);

  return (
    <div className="attendance-qr-wrap">
      <canvas ref={canvasRef} className="attendance-qr-canvas" aria-label="Attendance QR code" />
      <p className="attendance-qr-note">Refreshes automatically — project this code for students to scan.</p>
    </div>
  );
}
