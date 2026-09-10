const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('chatDesktop', {
  state: () => ipcRenderer.invoke('desktop:state'),
  openStudio: value => ipcRenderer.invoke('desktop:studio', value),
  start: values => ipcRenderer.invoke('desktop:start', values),
  stop: () => ipcRenderer.invoke('desktop:stop'),
  onState: callback => {
    const listener = (event, state) => callback(state);
    ipcRenderer.on('desktop:state', listener);
    return () => ipcRenderer.removeListener('desktop:state', listener);
  },
});
