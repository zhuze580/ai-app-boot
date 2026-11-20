using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Accessibility;

public static class AppBootNative {
    public static int InspectedNodes, TextNodes, LastTextState;
    [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
    delegate bool Visit(IntPtr h,IntPtr p);
    [DllImport("user32.dll")] static extern bool EnumWindows(Visit callback,IntPtr param);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
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
