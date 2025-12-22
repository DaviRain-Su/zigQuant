import React, { useState } from 'react';

const ZigQuantArchitecture = () => {
  const [selectedModule, setSelectedModule] = useState(null);
  const [activeTab, setActiveTab] = useState('overview');

  const modules = {
    ui: {
      name: 'User Interface Layer',
      color: '#3B82F6',
      description: 'CLI, TUI, Web UI, Telegram Bot, REST API',
      details: ['命令行界面 (CLI)', '终端 UI (TUI)', 'Web 仪表板', 'Telegram 机器人', 'REST API 服务'],
    },
    core: {
      name: 'Core Engine',
      color: '#10B981',
      description: '策略引擎、订单管理、风险控制、仓位追踪',
      details: ['策略调度器', '订单管理器', '风险管理器', '仓位追踪器', '事件总线', '投资组合管理'],
    },
    exchange: {
      name: 'Exchange Abstraction Layer',
      color: '#F59E0B',
      description: '统一交易所接口、智能路由、多交易所支持',
      details: ['IExchange 统一接口', '交易所路由器', '符号映射器', '连接池管理', '限流器'],
    },
    connectors: {
      name: 'Exchange Connectors',
      color: '#EF4444',
      description: 'Binance, OKX, Bybit, Kraken, Gate, DEX',
      details: ['Binance (现货+期货)', 'OKX', 'Bybit', 'Kraken', 'Gate.io', 'Uniswap V3'],
    },
    data: {
      name: 'Data Layer',
      color: '#8B5CF6',
      description: '订单簿缓存、K线存储、交易历史、行情缓存',
      details: ['订单簿聚合器', 'K线数据存储', '交易历史', 'Ticker 缓存', 'SQLite/TimescaleDB'],
    },
  };

  const flows = [
    { id: 'realtime', name: '实时数据流', icon: '📡' },
    { id: 'order', name: '订单执行流', icon: '📝' },
    { id: 'strategy', name: '策略执行流', icon: '🎯' },
    { id: 'backtest', name: '回测流程', icon: '📊' },
  ];

  const renderOverview = () => (
    <div className="space-y-4">
      {/* Architecture Diagram */}
      <div className="bg-gray-900 rounded-xl p-6 border border-gray-700">
        <h3 className="text-lg font-bold text-white mb-4 text-center">ZigQuant 系统架构</h3>
        
        {/* UI Layer */}
        <div 
          className={`p-4 rounded-lg mb-3 cursor-pointer transition-all border-2 ${selectedModule === 'ui' ? 'border-blue-400 shadow-lg shadow-blue-500/20' : 'border-transparent'}`}
          style={{ backgroundColor: modules.ui.color + '20' }}
          onClick={() => setSelectedModule(selectedModule === 'ui' ? null : 'ui')}
        >
          <div className="flex items-center justify-between">
            <span className="font-semibold text-blue-400">🖥️ {modules.ui.name}</span>
            <div className="flex gap-2">
              {['CLI', 'TUI', 'Web', 'Telegram', 'API'].map(item => (
                <span key={item} className="px-2 py-1 bg-blue-500/30 rounded text-xs text-blue-300">{item}</span>
              ))}
            </div>
          </div>
        </div>

        {/* Arrow */}
        <div className="flex justify-center my-2">
          <div className="text-gray-500 text-2xl">↓</div>
        </div>

        {/* Core Engine */}
        <div 
          className={`p-4 rounded-lg mb-3 cursor-pointer transition-all border-2 ${selectedModule === 'core' ? 'border-green-400 shadow-lg shadow-green-500/20' : 'border-transparent'}`}
          style={{ backgroundColor: modules.core.color + '20' }}
          onClick={() => setSelectedModule(selectedModule === 'core' ? null : 'core')}
        >
          <div className="font-semibold text-green-400 mb-2">⚙️ {modules.core.name}</div>
          <div className="grid grid-cols-3 gap-2">
            {['Strategy Engine', 'Order Manager', 'Risk Manager', 'Position Tracker', 'Event Bus', 'Portfolio'].map(item => (
              <div key={item} className="px-2 py-1 bg-green-500/20 rounded text-xs text-green-300 text-center">{item}</div>
            ))}
          </div>
        </div>

        {/* Arrow */}
        <div className="flex justify-center my-2">
          <div className="text-gray-500 text-2xl">↓</div>
        </div>

        {/* Exchange Abstraction */}
        <div 
          className={`p-4 rounded-lg mb-3 cursor-pointer transition-all border-2 ${selectedModule === 'exchange' ? 'border-yellow-400 shadow-lg shadow-yellow-500/20' : 'border-transparent'}`}
          style={{ backgroundColor: modules.exchange.color + '20' }}
          onClick={() => setSelectedModule(selectedModule === 'exchange' ? null : 'exchange')}
        >
          <div className="font-semibold text-yellow-400 mb-2">🔌 {modules.exchange.name}</div>
          <div className="flex justify-center gap-4">
            <div className="px-3 py-1 bg-yellow-500/20 rounded text-sm text-yellow-300">IExchange 接口</div>
            <div className="px-3 py-1 bg-yellow-500/20 rounded text-sm text-yellow-300">智能路由器</div>
            <div className="px-3 py-1 bg-yellow-500/20 rounded text-sm text-yellow-300">符号映射</div>
          </div>
        </div>

        {/* Arrow */}
        <div className="flex justify-center my-2">
          <div className="text-gray-500 text-2xl">↓</div>
        </div>

        {/* Connectors */}
        <div 
          className={`p-4 rounded-lg mb-3 cursor-pointer transition-all border-2 ${selectedModule === 'connectors' ? 'border-red-400 shadow-lg shadow-red-500/20' : 'border-transparent'}`}
          style={{ backgroundColor: modules.connectors.color + '20' }}
          onClick={() => setSelectedModule(selectedModule === 'connectors' ? null : 'connectors')}
        >
          <div className="font-semibold text-red-400 mb-2">🌐 {modules.connectors.name}</div>
          <div className="flex justify-center gap-2 flex-wrap">
            {['Binance', 'OKX', 'Bybit', 'Kraken', 'Gate', 'DEX'].map(ex => (
              <div key={ex} className="px-3 py-2 bg-red-500/20 rounded-lg text-sm text-red-300 font-medium">{ex}</div>
            ))}
          </div>
        </div>

        {/* Data Layer */}
        <div 
          className={`p-4 rounded-lg cursor-pointer transition-all border-2 ${selectedModule === 'data' ? 'border-purple-400 shadow-lg shadow-purple-500/20' : 'border-transparent'}`}
          style={{ backgroundColor: modules.data.color + '20' }}
          onClick={() => setSelectedModule(selectedModule === 'data' ? null : 'data')}
        >
          <div className="font-semibold text-purple-400 mb-2">💾 {modules.data.name}</div>
          <div className="flex justify-center gap-2">
            {['Orderbook', 'Klines', 'Trades', 'Ticker', 'SQLite'].map(item => (
              <div key={item} className="px-2 py-1 bg-purple-500/20 rounded text-xs text-purple-300">{item}</div>
            ))}
          </div>
        </div>
      </div>

      {/* Module Details */}
      {selectedModule && (
        <div className="bg-gray-800 rounded-xl p-4 border border-gray-700">
          <h4 className="font-bold text-white mb-2" style={{ color: modules[selectedModule].color }}>
            {modules[selectedModule].name}
          </h4>
          <p className="text-gray-400 text-sm mb-3">{modules[selectedModule].description}</p>
          <div className="space-y-1">
            {modules[selectedModule].details.map((detail, i) => (
              <div key={i} className="flex items-center gap-2 text-gray-300 text-sm">
                <span className="text-gray-500">•</span>
                {detail}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );

  const renderDataFlow = () => (
    <div className="bg-gray-900 rounded-xl p-6 border border-gray-700">
      <h3 className="text-lg font-bold text-white mb-4">📡 实时数据流</h3>
      
      <div className="space-y-3">
        {/* Exchanges */}
        <div className="flex justify-center gap-2">
          {['Binance', 'OKX', 'Bybit', 'Kraken'].map(ex => (
            <div key={ex} className="px-3 py-2 bg-blue-500/20 rounded text-blue-300 text-sm">{ex}</div>
          ))}
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓ WebSocket</div>
        
        {/* WebSocket Manager */}
        <div className="p-3 bg-green-500/20 rounded-lg text-center">
          <div className="text-green-400 font-semibold">WebSocket Manager</div>
          <div className="text-green-300 text-xs mt-1">连接池 • 自动重连 • 心跳检测</div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓ 标准化</div>
        
        {/* Normalizer */}
        <div className="p-3 bg-yellow-500/20 rounded-lg text-center">
          <div className="text-yellow-400 font-semibold">Message Normalizer</div>
          <div className="text-yellow-300 text-xs mt-1">统一格式 • 符号映射 • Decimal 转换</div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓</div>
        
        {/* Handlers */}
        <div className="flex justify-center gap-2">
          {[
            { name: 'Orderbook', color: 'purple' },
            { name: 'Ticker', color: 'pink' },
            { name: 'Trade', color: 'orange' },
          ].map(h => (
            <div key={h.name} className={`px-3 py-2 bg-${h.color}-500/20 rounded text-${h.color}-300 text-sm`}
                 style={{ backgroundColor: `rgb(var(--${h.color}-500) / 0.2)` }}>
              {h.name} Handler
            </div>
          ))}
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓</div>
        
        {/* Event Bus */}
        <div className="p-3 bg-red-500/20 rounded-lg text-center">
          <div className="text-red-400 font-semibold">Event Bus</div>
          <div className="text-red-300 text-xs mt-1">ticker_update • orderbook_update • trade_update</div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓ 订阅</div>
        
        {/* Consumers */}
        <div className="flex justify-center gap-2">
          {['Strategy Engine', 'Risk Manager', 'Monitor'].map(c => (
            <div key={c} className="px-3 py-2 bg-gray-700 rounded text-gray-300 text-sm">{c}</div>
          ))}
        </div>
      </div>
    </div>
  );

  const renderOrderFlow = () => (
    <div className="bg-gray-900 rounded-xl p-6 border border-gray-700">
      <h3 className="text-lg font-bold text-white mb-4">📝 订单执行流程</h3>
      
      <div className="space-y-3">
        {/* Strategy Signal */}
        <div className="p-3 bg-blue-500/20 rounded-lg">
          <div className="text-blue-400 font-semibold text-center">1️⃣ Strategy Signal</div>
          <div className="text-blue-300 text-xs text-center mt-1">方向 • 强度 • 元数据</div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓</div>
        
        {/* Order Builder */}
        <div className="p-3 bg-green-500/20 rounded-lg">
          <div className="text-green-400 font-semibold text-center">2️⃣ Order Builder</div>
          <div className="text-green-300 text-xs text-center mt-1">交易对 • 数量 • 价格 • 类型</div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓</div>
        
        {/* Risk Check */}
        <div className="p-3 bg-yellow-500/20 rounded-lg">
          <div className="text-yellow-400 font-semibold text-center">3️⃣ Risk Validation</div>
          <div className="flex justify-center gap-2 mt-1">
            {['仓位限制', '日损限制', '订单大小', '价格检查'].map(c => (
              <span key={c} className="text-yellow-300 text-xs bg-yellow-500/20 px-1 rounded">{c}</span>
            ))}
          </div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓</div>
        
        {/* Exchange Router */}
        <div className="p-3 bg-orange-500/20 rounded-lg">
          <div className="text-orange-400 font-semibold text-center">4️⃣ Exchange Router</div>
          <div className="text-orange-300 text-xs text-center mt-1">选择交易所 • 格式化 • 签名 • 限流</div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓ 智能路由</div>
        
        {/* Exchanges */}
        <div className="flex justify-center gap-2">
          {['Binance', 'OKX', 'Bybit'].map(ex => (
            <div key={ex} className="px-3 py-2 bg-red-500/20 rounded text-red-300 text-sm">{ex}</div>
          ))}
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓</div>
        
        {/* Order Tracker */}
        <div className="p-3 bg-purple-500/20 rounded-lg">
          <div className="text-purple-400 font-semibold text-center">5️⃣ Order Tracker</div>
          <div className="text-purple-300 text-xs text-center mt-1">存储 • 监控状态 • 处理成交 • 超时管理</div>
        </div>
        
        <div className="flex justify-center text-gray-500 text-xl">↓</div>
        
        {/* Position Manager */}
        <div className="p-3 bg-pink-500/20 rounded-lg">
          <div className="text-pink-400 font-semibold text-center">6️⃣ Position Manager</div>
          <div className="text-pink-300 text-xs text-center mt-1">更新仓位 • 计算盈亏 • 触发止损</div>
        </div>
      </div>
    </div>
  );

  const renderMultiExchange = () => (
    <div className="bg-gray-900 rounded-xl p-6 border border-gray-700">
      <h3 className="text-lg font-bold text-white mb-4">🔌 多交易所抽象</h3>
      
      <div className="space-y-4">
        {/* Interface */}
        <div className="p-4 bg-blue-500/20 rounded-lg border border-blue-500/30">
          <div className="text-blue-400 font-bold mb-2">IExchange 统一接口</div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="text-blue-300">• getTicker(pair)</div>
            <div className="text-blue-300">• getOrderbook(pair)</div>
            <div className="text-blue-300">• createOrder(request)</div>
            <div className="text-blue-300">• cancelOrder(id)</div>
            <div className="text-blue-300">• getBalance()</div>
            <div className="text-blue-300">• subscribeOrderbook()</div>
          </div>
        </div>
        
        {/* Router */}
        <div className="p-4 bg-yellow-500/20 rounded-lg border border-yellow-500/30">
          <div className="text-yellow-400 font-bold mb-2">Exchange Router</div>
          <div className="flex flex-wrap gap-2">
            {['最优价格', '最低费率', '订单分割', '轮询', '加权分配'].map(s => (
              <span key={s} className="px-2 py-1 bg-yellow-500/20 rounded text-yellow-300 text-xs">{s}</span>
            ))}
          </div>
        </div>
        
        {/* Registry */}
        <div className="p-4 bg-green-500/20 rounded-lg border border-green-500/30">
          <div className="text-green-400 font-bold mb-2">Exchange Registry</div>
          <div className="text-green-300 text-sm">动态注册 • 工厂模式 • 连接状态管理</div>
        </div>
        
        {/* Connectors */}
        <div className="grid grid-cols-3 gap-2">
          {[
            { name: 'Binance', features: ['现货', '期货', 'WebSocket'] },
            { name: 'OKX', features: ['现货', '期货', 'WebSocket'] },
            { name: 'Bybit', features: ['现货', '期货', 'WebSocket'] },
            { name: 'Kraken', features: ['现货', 'WebSocket'] },
            { name: 'Gate', features: ['现货', '期货'] },
            { name: 'Uniswap', features: ['AMM', 'Web3'] },
          ].map(ex => (
            <div key={ex.name} className="p-3 bg-gray-800 rounded-lg border border-gray-600">
              <div className="text-white font-semibold text-sm">{ex.name}</div>
              <div className="flex flex-wrap gap-1 mt-1">
                {ex.features.map(f => (
                  <span key={f} className="text-xs text-gray-400 bg-gray-700 px-1 rounded">{f}</span>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-gray-950 p-6">
      <div className="max-w-4xl mx-auto">
        {/* Header */}
        <div className="text-center mb-6">
          <h1 className="text-3xl font-bold text-white mb-2">⚡ ZigQuant</h1>
          <p className="text-gray-400">高性能量化交易框架 · Zig 实现</p>
        </div>
        
        {/* Tabs */}
        <div className="flex gap-2 mb-6 overflow-x-auto pb-2">
          {[
            { id: 'overview', name: '架构总览', icon: '🏗️' },
            { id: 'dataflow', name: '数据流', icon: '📡' },
            { id: 'orderflow', name: '订单流', icon: '📝' },
            { id: 'exchange', name: '多交易所', icon: '🔌' },
          ].map(tab => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-2 rounded-lg font-medium whitespace-nowrap transition-all ${
                activeTab === tab.id
                  ? 'bg-blue-600 text-white'
                  : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
              }`}
            >
              {tab.icon} {tab.name}
            </button>
          ))}
        </div>
        
        {/* Content */}
        {activeTab === 'overview' && renderOverview()}
        {activeTab === 'dataflow' && renderDataFlow()}
        {activeTab === 'orderflow' && renderOrderFlow()}
        {activeTab === 'exchange' && renderMultiExchange()}
        
        {/* Features */}
        <div className="mt-6 grid grid-cols-2 md:grid-cols-4 gap-3">
          {[
            { icon: '🚀', title: '高性能', desc: 'Zig 零成本抽象' },
            { icon: '🔒', title: '内存安全', desc: '编译时检查' },
            { icon: '🌐', title: '多交易所', desc: '统一接口抽象' },
            { icon: '📊', title: '完整回测', desc: '超参数优化' },
          ].map(f => (
            <div key={f.title} className="p-3 bg-gray-800 rounded-lg border border-gray-700">
              <div className="text-2xl mb-1">{f.icon}</div>
              <div className="text-white font-semibold text-sm">{f.title}</div>
              <div className="text-gray-400 text-xs">{f.desc}</div>
            </div>
          ))}
        </div>
        
        {/* Timeline */}
        <div className="mt-6 p-4 bg-gray-800 rounded-xl border border-gray-700">
          <h3 className="text-white font-bold mb-3">📅 开发时间线</h3>
          <div className="flex gap-2 overflow-x-auto pb-2">
            {[
              { phase: 'P0', name: '基础+抽象', weeks: '3-4周', color: 'blue' },
              { phase: 'P1', name: 'MVP', weeks: '3-4周', color: 'green' },
              { phase: 'P2', name: '交易引擎', weeks: '5-6周', color: 'yellow' },
              { phase: 'P3', name: '策略框架', weeks: '4-5周', color: 'orange' },
              { phase: 'P4', name: '回测系统', weeks: '4-5周', color: 'red' },
              { phase: 'P5', name: '做市套利', weeks: '5-6周', color: 'purple' },
              { phase: 'P6', name: '生产功能', weeks: '4-5周', color: 'pink' },
            ].map((p, i) => (
              <div key={p.phase} className="flex-shrink-0 text-center">
                <div className={`w-12 h-12 rounded-full bg-${p.color}-500/20 border-2 border-${p.color}-500 flex items-center justify-center text-${p.color}-400 font-bold mb-1`}
                     style={{ borderColor: `var(--${p.color}-500, #888)` }}>
                  {p.phase}
                </div>
                <div className="text-white text-xs font-medium">{p.name}</div>
                <div className="text-gray-500 text-xs">{p.weeks}</div>
              </div>
            ))}
          </div>
          <div className="text-center text-gray-400 text-sm mt-2">
            总计: <span className="text-white font-bold">7-9 个月</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ZigQuantArchitecture;
