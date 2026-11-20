export class CDP {
  constructor(ws) {
    this.ws=ws;this.next=0;this.pending=new Map();
    ws.addEventListener('message',e=>{
      let m;try{m=JSON.parse(e.data);}catch{return;}
      const item=this.pending.get(m.id);if(!item)return;
      clearTimeout(item.timer);this.pending.delete(m.id);
      m.error?item.reject(new Error('protocol-error')):item.resolve(m.result);
    });
    ws.addEventListener('close',()=>{
      for(const item of this.pending.values()){clearTimeout(item.timer);item.reject(new Error('disconnected'));}
      this.pending.clear();
    });
  }
  static async open(url) {
    const ws=new WebSocket(url);
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{try{ws.close();}catch{}reject(new Error('connect-timeout'));},3500);
      ws.addEventListener('open',()=>{clearTimeout(timer);resolve();},{once:true});
      ws.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('connection'));},{once:true});
    });
    return new CDP(ws);
  }
  call(method,params={},timeout=8000) {
    return new Promise((resolve,reject)=>{
      const id=++this.next;
      const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error('timeout'));},timeout);
      this.pending.set(id,{resolve,reject,timer});
      try{this.ws.send(JSON.stringify({id,method,params}));}
      catch{clearTimeout(timer);this.pending.delete(id);reject(new Error('disconnected'));}
    });
  }
  async evaluate(expression,timeout=8000) {
    const r=await this.call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},timeout);
    if(r.exceptionDetails)throw new Error('renderer-error');
    return r.result?.value;
  }
  close(){this.ws.close();}
}
