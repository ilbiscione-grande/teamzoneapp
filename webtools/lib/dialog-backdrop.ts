import type { MouseEvent, PointerEvent } from 'react';

/** Dismiss only a click that starts and finishes on the native backdrop. */
export function dialogBackdropHandlers() {
  let startedOutside = false;
  const outside = (event: MouseEvent<HTMLDialogElement> | PointerEvent<HTMLDialogElement>) => {
    if (event.target !== event.currentTarget) return false;
    const box = event.currentTarget.getBoundingClientRect();
    return event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom;
  };
  return {
    onPointerDown(event: PointerEvent<HTMLDialogElement>) { startedOutside = event.button === 0 && outside(event); },
    onPointerCancel() { startedOutside = false; },
    onClick(event: MouseEvent<HTMLDialogElement>) {
      const dismiss = startedOutside && outside(event);
      startedOutside = false;
      if (!dismiss) return;
      event.preventDefault();
      event.stopPropagation();
      event.currentTarget.close();
    },
  };
}
