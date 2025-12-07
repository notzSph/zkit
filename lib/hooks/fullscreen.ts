import { useEffect, useState } from "react";


export function useFullscreen(id: string) {

    const [isFullScreen, setIsFullScreen] = useState(false);

    useEffect(() => {
        const fullscreenChange = (event: any,) => {
            setIsFullScreen(document.fullscreenElement?.id === id)
        }
        window.addEventListener('fullscreenchange' as any, fullscreenChange)
        return () => window.removeEventListener('fullscreenchange' as any, fullscreenChange);
    })
    return isFullScreen
}
