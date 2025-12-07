"use client";
import { useEffect, useState } from 'react';
import { BehaviorSubject } from 'rxjs';

/**  Layout
*  
*  Layout State Manager
*  @param isDesktop ---> Desktop Layout Flag
*  @param isTablet  ---> Tablet Layout Flag
*  @param isMobile  ---> Mobile Layout Flag
*  
*/
export interface Layout {
  isDesktop: boolean;
  isTablet: boolean;
  isMobile: boolean;
}

const layout$ = new BehaviorSubject<Layout>({
  isDesktop: false,
  isTablet: false,
  isMobile: false,
});

/** Internal: update the BehaviorSubject on resize */
function handleResize() {
  layout$.next({
    isDesktop: window.innerWidth >= 1024,
    isTablet: window.innerWidth >= 768 && window.innerWidth < 1024,
    isMobile: window.innerWidth < 768,
  });
}

/** Hook: sets up the resize listener once */
export function useLayoutListener(): void {
  useEffect(() => {
    handleResize();
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);
}

/** Hook: subscribes to layout$ and returns flags */
export function useLayout(): Layout {
  const [layout, setLayout] = useState<Layout>({
    isDesktop: false,
    isTablet: false,
    isMobile: false,
  });

  useEffect(() => {
    const sub = layout$.subscribe(setLayout);
    return () => sub.unsubscribe();
  }, []);

  return layout;
}