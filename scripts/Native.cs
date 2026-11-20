using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Accessibility;

public static class AppBootNative {
    public static int InspectedNodes, TextNodes, LastTextState;
    [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
    delegate bool Visit(IntPtr h,IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(Visit callback,IntPtr param);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent,Visit callback,IntPtr param);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out Rect r);
    [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref Point p);
    [DllImport("user32.dll")] static extern int GetClassName(IntPtr h,System.Text.StringBuilder text,int max);
    [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h,System.Text.StringBuilder text,int max);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int command);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint from,uint to,bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h,int attr,ref int value,int size);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h,int attr,out int value,int size);

    public static IntPtr FindHidden(uint pid) {
        IntPtr found=IntPtr.Zero;
        EnumWindows((h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);
            if(owner!=pid||IsWindowVisible(h)||(GetWindowLong(h,-20)&0x80)!=0)return true;
            var cls=new System.Text.StringBuilder(256);var title=new System.Text.StringBuilder(512);
            GetClassName(h,cls,256);GetWindowText(h,title,512);
            if(cls.ToString()=="Chrome_WidgetWin_1"&&IsAppTitle(title.ToString())){found=h;return false;}return true;
        },IntPtr.Zero);
        return found;
    }
    static bool IsAppTitle(string title) {return title=="ChatGPT"||title=="Codex"||title=="WorkBuddy"||title=="WorkBuddy AI";}
    public static IntPtr FindMain(uint pid) {
        IntPtr found=IntPtr.Zero;
        EnumWindows((h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);
            if(owner!=pid||!IsWindowVisible(h)||(GetWindowLong(h,-20)&0x80)!=0)return true;
            var title=new System.Text.StringBuilder(512);GetWindowText(h,title,512);
            if(IsAppTitle(title.ToString())){found=h;return false;}return true;
        },IntPtr.Zero);
        return found;
    }
    public static bool Visible(IntPtr h) {int cloaked;return IsWindowVisible(h)&&!IsIconic(h)&&(DwmGetWindowAttribute(h,14,out cloaked,4)!=0||cloaked==0);}
    public static void Restore(IntPtr h) {ShowWindow(h,IsIconic(h)?9:5);}
    public static bool Activate(IntPtr h) {
        Restore(h);SetForegroundWindow(h);
        if(GetForegroundWindow()==h)return true;
        uint owner;uint other=GetWindowThreadProcessId(GetForegroundWindow(),out owner),current=GetCurrentThreadId();bool attached=false;
        try {if(other!=0&&other!=current)attached=AttachThreadInput(current,other,true);BringWindowToTop(h);SetForegroundWindow(h);}
        finally {if(attached)AttachThreadInput(current,other,false);}
        return Visible(h)&&GetForegroundWindow()==h;
    }
    public static bool Cover(IntPtr splash,Rect target) {
        // WS_CAPTION | WS_THICKFRAME | WS_BORDER | WS_DLGFRAME. Also remove extended client/window edges.
        SetWindowLong(splash,-16,GetWindowLong(splash,-16)&~0x00CF0000);
        SetWindowLong(splash,-20,GetWindowLong(splash,-20)&~0x00020301);
        int square=1;DwmSetWindowAttribute(splash,33,ref square,4);
        SetWindowPos(splash,new IntPtr(-1),target.Left,target.Top,target.Right-target.Left,target.Bottom-target.Top,0x0030);
        Rect client;Point origin=new Point();
        if(!GetClientRect(splash,out client)||!ClientToScreen(splash,ref origin))return false;
        int left=origin.X-target.Left,top=origin.Y-target.Top;
        // Correct any residual Chromium non-client inset using actual physical client pixels.
        int width=target.Right-target.Left+left+(target.Right-(origin.X+client.Right));
        int height=target.Bottom-target.Top+top+(target.Bottom-(origin.Y+client.Bottom));
        if(left!=0||top!=0||client.Right<target.Right-target.Left||client.Bottom<target.Bottom-target.Top)
            SetWindowPos(splash,new IntPtr(-1),target.Left-left,target.Top-top,width,height,0x0030);
        return true;
    }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h,int index);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h,int index,int value);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h,int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr h,uint objectId,ref Guid iid,[MarshalAs(UnmanagedType.Interface)] out IAccessible acc);
    [DllImport("oleacc.dll")] static extern int AccessibleChildren(IAccessible parent,int start,int count,[Out,MarshalAs(UnmanagedType.LPArray,SizeParamIndex=2)] object[] children,out int obtained);

    public static IntPtr Find(uint pid) {
        IntPtr found=IntPtr.Zero;long largest=0;
        EnumWindows((h,p)=>{uint owner;GetWindowThreadProcessId(h,out owner);Rect r;
            if(owner==pid&&IsWindowVisible(h)&&(GetWindowLong(h,-20)&0x80)==0&&GetWindowRect(h,out r)){
                if(IsIconic(h)){found=h;return false;}
                long area=(long)(r.Right-r.Left)*(r.Bottom-r.Top);
                if(r.Right-r.Left>200&&r.Bottom-r.Top>150&&area>largest){found=h;largest=area;}
            }
            return true;
        },IntPtr.Zero);
        return found;
    }

    // Roles/states and fixed navigation labels only. No input values, chat contents, URLs or account data are returned.
    public static bool PageReady(IntPtr window) {
        Guid id=typeof(IAccessible).GUID;IAccessible root;
        if(AccessibleObjectFromWindow(window,0xFFFFFFFC,ref id,out root)!=0||root==null)return false;
        var queue=new Queue<IAccessible>();queue.Enqueue(root);
        EnumChildWindows(window,(h,p)=>{var cls=new System.Text.StringBuilder(256);GetClassName(h,cls,256);
            if(cls.ToString()=="Chrome_RenderWidgetHostHWND"){IAccessible page;Guid pageId=typeof(IAccessible).GUID;if(AccessibleObjectFromWindow(h,0xFFFFFFFC,ref pageId,out page)==0&&page!=null)queue.Enqueue(page);}return true;
        },IntPtr.Zero);
        int visited=0;bool editor=false,navigation=false;
        InspectedNodes=0;TextNodes=0;LastTextState=0;
        while(queue.Count>0&&visited<1800) {
            var parent=queue.Dequeue();
            try {
                int count=Math.Min(parent.accChildCount,1800-visited);
                var children=new object[count];int obtained;
                AccessibleChildren(parent,0,count,children,out obtained);
                for(int i=0;i<obtained;i++) {
                    visited++;
                    var node=children[i] as IAccessible;
                    if(node==null&&children[i]!=null){try{node=parent.get_accChild(children[i]) as IAccessible;}catch{}}
                    var owner=node??parent;object child=node!=null?(object)0:children[i];
                    if(child==null)continue;
                    try {
                        int role=Convert.ToInt32(owner.get_accRole(child));
                        int state=Convert.ToInt32(owner.get_accState(child));
                        InspectedNodes=visited;
                        if(role==42){TextNodes++;LastTextState=state;}
                        // ROLE_SYSTEM_TEXT, writable, focusable, visible, available.
                        if(role==42&&(state&0x100000)!=0&&(state&(0x40|0x8000|0x10000|0x1|0x20000000))==0)editor=true;
                        if(role==43&&(state&(0x8000|0x10000|0x1))==0) {
                            string name=owner.get_accName(child)??"";
                            if(System.Text.RegularExpressions.Regex.IsMatch(name,"^(搜索|Search|新对话|新建任务|新任务|New chat|New task|收起侧边栏|Toggle sidebar)",System.Text.RegularExpressions.RegexOptions.IgnoreCase))navigation=true;
                        }
                        if(editor&&navigation)return true;
                        if(node!=null)queue.Enqueue(node);
                    }catch{}
                }
            }catch{}
        }
        return false;
    }
}
