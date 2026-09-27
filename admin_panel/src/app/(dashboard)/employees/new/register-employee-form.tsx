"use client";

import { useEffect, useRef, useState, useTransition, type FormEvent } from "react";
import { registerEmployee } from "../actions";

type Capture = { id: string; blob: Blob; previewUrl: string };

const MIN_PHOTOS = 3;
const MAX_PHOTOS = 5;

export function RegisterEmployeeForm() {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [cameraReady, setCameraReady] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);
  const [captures, setCaptures] = useState<Capture[]>([]);
  const [isPending, startTransition] = useTransition();

  async function startCamera() {
    setCameraError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: 640, height: 480 },
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play();
      }
      setCameraReady(true);
    } catch (err) {
      setCameraError(err instanceof Error ? err.message : "Could not access camera");
    }
  }

  function stopCamera() {
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = null;
    setCameraReady(false);
  }

  // Safety net for the "Stop camera" button: these are photos of children,
  // so the stream must not keep running if the admin navigates away (e.g.
  // submits the form, which redirect()s client-side rather than reloading
  // the page) without explicitly stopping it first.
  useEffect(() => {
    return () => {
      streamRef.current?.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    };
  }, []);

  function capturePhoto() {
    const video = videoRef.current;
    if (!video) return;

    const canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

    canvas.toBlob(
      (blob) => {
        if (!blob) return;
        setCaptures((prev) =>
          prev.length >= MAX_PHOTOS
            ? prev
            : [
                ...prev,
                { id: crypto.randomUUID(), blob, previewUrl: URL.createObjectURL(blob) },
              ],
        );
      },
      "image/jpeg",
      0.9,
    );
  }

  function removeCapture(id: string) {
    setCaptures((prev) => {
      const target = prev.find((c) => c.id === id);
      if (target) URL.revokeObjectURL(target.previewUrl);
      return prev.filter((c) => c.id !== id);
    });
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formData = new FormData(event.currentTarget);
    captures.forEach((capture, index) => {
      formData.append(
        "photos",
        new File([capture.blob], `photo-${index}.jpg`, { type: "image/jpeg" }),
      );
    });
    // Photos are already captured into formData -- release the camera
    // before submitting rather than leaving it running through the
    // (possibly slow) upload + redirect.
    stopCamera();
    startTransition(() => {
      registerEmployee(formData);
    });
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <Field label="Full name" name="full_name" required />
        <Field label="Student code" name="employee_code" />
        <Field label="Email" name="email" type="email" />
        <Field label="Phone" name="phone" />
        <Field label="Department" name="department" />
        <Field label="Standard" name="standard" />
        <Field label="Section" name="section" />
        <GenderSelect />
      </div>

      <div className="space-y-4 rounded-xl border border-slate-200 p-4">
        <div>
          <h2 className="text-sm font-medium text-slate-900">Parent / guardian details</h2>
          <p className="text-xs text-slate-500">
            Used to contact a parent about their child&apos;s attendance. Optional, but at least
            one phone number is recommended.
          </p>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div className="space-y-4">
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Mother</p>
            <Field label="Name" name="mother_name" />
            <Field label="Phone" name="mother_phone" />
            <Field label="Email" name="mother_email" type="email" />
          </div>
          <div className="space-y-4">
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Father</p>
            <Field label="Name" name="father_name" />
            <Field label="Phone" name="father_phone" />
            <Field label="Email" name="father_email" type="email" />
          </div>
        </div>
      </div>

      <div className="rounded-xl border border-slate-200 p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium text-slate-900">
            Enrollment photos ({captures.length}/{MAX_PHOTOS})
          </h2>
          {!cameraReady ? (
            <button
              type="button"
              onClick={startCamera}
              className="text-sm font-medium text-slate-900 underline"
            >
              Start camera
            </button>
          ) : (
            <button type="button" onClick={stopCamera} className="text-sm text-slate-500 underline">
              Stop camera
            </button>
          )}
        </div>

        {cameraError && <p className="mt-2 text-sm text-red-600">{cameraError}</p>}

        <div className="mt-3 flex flex-wrap items-start gap-4">
          <div className="overflow-hidden rounded-lg bg-slate-900">
            <video ref={videoRef} muted playsInline className="h-48 w-64 object-cover" />
          </div>

          <div className="flex flex-1 flex-wrap gap-2">
            {captures.map((capture) => (
              <div key={capture.id} className="relative">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={capture.previewUrl}
                  alt="Captured face"
                  className="h-20 w-20 rounded-md object-cover"
                />
                <button
                  type="button"
                  onClick={() => removeCapture(capture.id)}
                  className="absolute -right-2 -top-2 flex h-5 w-5 items-center justify-center rounded-full bg-slate-900 text-xs text-white"
                >
                  ×
                </button>
              </div>
            ))}
          </div>
        </div>

        <button
          type="button"
          onClick={capturePhoto}
          disabled={!cameraReady || captures.length >= MAX_PHOTOS}
          className="mt-4 rounded-md border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 disabled:opacity-40"
        >
          Capture photo
        </button>
        {captures.length < MIN_PHOTOS && (
          <p className="mt-2 text-xs text-slate-500">
            Capture at least {MIN_PHOTOS} photos from different angles.
          </p>
        )}
      </div>

      <button
        type="submit"
        disabled={isPending || captures.length < MIN_PHOTOS}
        className="rounded-md bg-indigo-600 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-500 disabled:opacity-40"
      >
        {isPending ? "Registering..." : "Register student"}
      </button>
    </form>
  );
}

function GenderSelect() {
  return (
    <div className="space-y-1">
      <label htmlFor="gender" className="text-sm font-medium text-slate-700">
        Gender
      </label>
      <select
        id="gender"
        name="gender"
        defaultValue=""
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      >
        <option value="">Not specified</option>
        <option value="male">Boy</option>
        <option value="female">Girl</option>
        <option value="other">Other</option>
      </select>
    </div>
  );
}

function Field({
  label,
  name,
  type = "text",
  required,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
}) {
  return (
    <div className="space-y-1">
      <label htmlFor={name} className="text-sm font-medium text-slate-700">
        {label}
      </label>
      <input
        id={name}
        name={name}
        type={type}
        required={required}
        className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-500"
      />
    </div>
  );
}
